"""Server-side ingestion of inbound trip-WebSocket frames.

Each `location` frame is persisted to the TimescaleDB hypertable, and we
check whether the publisher just entered the arrival radius of any
waypoint. When that happens we emit a system `arrival` chat message which
is also persisted and re-fanned-out via Redis.

Each `message` frame is persisted to the messages table.

Keeping this in a service module (rather than the WS handler) means tests
can drive ingestion directly without spinning a real socket.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import SessionLocal
from ..models.message import Message
from ..models.trip import TripMember
from ..models.user import User
from ..models.waypoint import Waypoint
from ..redis import online_user_ids
from .push import push_chat_to_users

_INSERT_LOCATION = text(
    """
    INSERT INTO locations
        (user_id, trip_id, geom, heading, speed_mps, battery_pct, recorded_at)
    VALUES
        (
            :user_id,
            :trip_id,
            ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography,
            :heading,
            :speed,
            :battery,
            :recorded_at
        )
    ON CONFLICT (user_id, trip_id, recorded_at) DO NOTHING
    """
)


async def ingest_frame(
    *, trip_id: uuid.UUID, user_id: uuid.UUID, frame: dict[str, Any]
) -> list[dict[str, Any]]:
    """Persist whatever the frame represents and return any extra system
    frames (like geofence arrivals) that should also be fanned out."""
    kind = frame.get("type")
    if kind == "location":
        return await _ingest_location(trip_id, user_id, frame)
    if kind == "message":
        await _ingest_message(trip_id, user_id, frame)
    return []


async def _ingest_location(
    trip_id: uuid.UUID, user_id: uuid.UUID, frame: dict[str, Any]
) -> list[dict[str, Any]]:
    lat = frame.get("lat")
    lng = frame.get("lng")
    if lat is None or lng is None:
        return []
    recorded_at = _parse_timestamp(frame.get("t"))

    async with SessionLocal() as session:
        await session.execute(
            _INSERT_LOCATION,
            {
                "user_id": user_id,
                "trip_id": trip_id,
                "lng": float(lng),
                "lat": float(lat),
                "heading": frame.get("hdg"),
                "speed": frame.get("spd"),
                "battery": frame.get("bat"),
                "recorded_at": recorded_at,
            },
        )
        await session.commit()

        return await _maybe_emit_arrival(
            session=session,
            trip_id=trip_id,
            user_id=user_id,
            lat=float(lat),
            lng=float(lng),
        )


async def _ingest_message(
    trip_id: uuid.UUID, user_id: uuid.UUID, frame: dict[str, Any]
) -> None:
    body = (frame.get("body") or "").strip()
    if not body:
        return
    async with SessionLocal() as session:
        session.add(
            Message(trip_id=trip_id, user_id=user_id, body=body, kind="text")
        )
        await session.commit()
        await _push_to_offline_members(
            session=session, trip_id=trip_id, sender_id=user_id, body=body
        )


async def _push_to_offline_members(
    *,
    session: AsyncSession,
    trip_id: uuid.UUID,
    sender_id: uuid.UUID,
    body: str,
) -> None:
    """FCM push to every trip member that isn't currently watching the WS."""
    online = await online_user_ids(str(trip_id))
    member_rows = (
        await session.scalars(
            select(TripMember.user_id).where(
                TripMember.trip_id == trip_id,
                TripMember.left_at.is_(None),
            )
        )
    ).all()
    targets = [
        str(uid)
        for uid in member_rows
        if str(uid) not in online and uid != sender_id
    ]
    if not targets:
        return
    sender = await session.get(User, sender_id)
    title = sender.display_name if sender and sender.display_name else "PackPath"
    await push_chat_to_users(
        session=session,
        user_ids=targets,
        title=title,
        body=body,
        data={"trip_id": str(trip_id), "kind": "chat"},
    )


async def _maybe_emit_arrival(
    *,
    session: AsyncSession,
    trip_id: uuid.UUID,
    user_id: uuid.UUID,
    lat: float,
    lng: float,
) -> list[dict[str, Any]]:
    point = func.ST_SetSRID(func.ST_MakePoint(lng, lat), 4326).cast(
        Waypoint.geom.type
    )
    rows = (
        await session.execute(
            select(
                Waypoint.id,
                Waypoint.name,
                Waypoint.arrival_radius_m,
                func.ST_Distance(Waypoint.geom, point).label("distance_m"),
            )
            .where(Waypoint.trip_id == trip_id)
            .order_by(func.ST_Distance(Waypoint.geom, point).asc())
        )
    ).all()
    if not rows:
        return []
    nearest = rows[0]
    distance = nearest.distance_m
    if distance is None or distance > nearest.arrival_radius_m:
        return []

    # De-dupe: don't spam the channel if we already announced this arrival
    # for the same user/waypoint in the last 5 minutes.
    recent = await session.scalar(
        select(Message)
        .where(
            Message.trip_id == trip_id,
            Message.user_id == user_id,
            Message.kind == "arrival",
            Message.body.like(f"%{nearest.name}%"),
            Message.sent_at > _now_minus(minutes=5),
        )
        .limit(1)
    )
    if recent is not None:
        return []

    body = f"arrived at {nearest.name}"
    session.add(
        Message(trip_id=trip_id, user_id=user_id, body=body, kind="arrival")
    )
    await session.commit()
    return [
        {
            "type": "arrival",
            "user_id": str(user_id),
            "waypoint_id": str(nearest.id),
            "waypoint_name": nearest.name,
        }
    ]


def _parse_timestamp(value: Any) -> datetime:
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            pass
    return datetime.now(tz=timezone.utc)


def _now_minus(*, minutes: int) -> datetime:
    return datetime.now(tz=timezone.utc) - timedelta(minutes=minutes)

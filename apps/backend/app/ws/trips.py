"""Per-trip WebSocket gateway with Redis pub/sub fan-out.

Each connected client subscribes to `trip:{trip_id}` on Redis. Anything
published on that channel is forwarded to the client. Anything the client
sends is published, so other backend pods see it too.

Client → server message envelope:
    { "type": "location" | "message" | "typing" | "ghost", ... }
"""

from __future__ import annotations

import asyncio
import json
import time
import uuid

from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect, status
from loguru import logger
from sqlalchemy import select

from ..db import SessionLocal
from ..models.trip import TripMember
from ..redis import (
    get_redis,
    mark_offline,
    mark_online,
    publish_trip,
    trip_channel,
)
from ..security import decode_token
from ..services.ingest import ingest_frame
from ..services.visibility import visible_member_ids

# How long a connection caches its "who can I see" set before refreshing.
_VISIBILITY_CACHE_TTL_S = 10.0

router = APIRouter()


async def _authenticate(token: str) -> uuid.UUID | None:
    try:
        claims = decode_token(token)
    except ValueError:
        return None
    if claims.get("type") != "access":
        return None
    sub = claims.get("sub")
    return uuid.UUID(sub) if sub else None


async def _is_member(user_id: uuid.UUID, trip_id: uuid.UUID) -> bool:
    async with SessionLocal() as session:
        member = await session.scalar(
            select(TripMember).where(
                TripMember.trip_id == trip_id,
                TripMember.user_id == user_id,
                TripMember.left_at.is_(None),
            )
        )
        return member is not None


async def _is_ghost(user_id: uuid.UUID, trip_id: uuid.UUID) -> bool:
    async with SessionLocal() as session:
        member = await session.scalar(
            select(TripMember).where(
                TripMember.trip_id == trip_id,
                TripMember.user_id == user_id,
                TripMember.left_at.is_(None),
            )
        )
        return bool(member and member.ghost_mode)


@router.websocket("/ws/trips/{trip_id}")
async def trip_socket(
    websocket: WebSocket,
    trip_id: uuid.UUID,
    token: str = Query(...),
) -> None:
    user_id = await _authenticate(token)
    if user_id is None:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return
    if not await _is_member(user_id, trip_id):
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return

    await websocket.accept()
    logger.info("ws connected user={} trip={}", user_id, trip_id)

    await mark_online(str(trip_id), str(user_id))

    pubsub = get_redis().pubsub()
    await pubsub.subscribe(trip_channel(str(trip_id)))

    # Announce presence to other peers
    await publish_trip(
        str(trip_id),
        json.dumps({"type": "presence", "user_id": str(user_id), "state": "joined"}),
    )

    # Per-connection cache of which members' locations this viewer may see,
    # so we can filter the shared trip channel per-recipient (ghost mode is
    # already dropped at publish; this also enforces share_until / scope).
    visible_cache: set[uuid.UUID] = set()
    visible_at = 0.0

    async def _may_see_location(sender_id: uuid.UUID) -> bool:
        nonlocal visible_cache, visible_at
        if sender_id == user_id:
            return True
        now = time.monotonic()
        if now - visible_at > _VISIBILITY_CACHE_TTL_S:
            async with SessionLocal() as session:
                visible_cache = await visible_member_ids(
                    session, trip_id, user_id
                )
            visible_at = now
        return sender_id in visible_cache

    async def _pump_redis_to_ws() -> None:
        async for message in pubsub.listen():
            if message.get("type") != "message":
                continue
            data = message["data"]
            # Filter location frames the viewer isn't permitted to see.
            try:
                frame = json.loads(data)
            except (json.JSONDecodeError, TypeError):
                frame = None
            if frame is not None and frame.get("type") == "location":
                sender = frame.get("user_id")
                if sender is not None:
                    try:
                        sender_id = uuid.UUID(str(sender))
                    except ValueError:
                        continue
                    if not await _may_see_location(sender_id):
                        continue
            await websocket.send_text(data)

    redis_task = asyncio.create_task(_pump_redis_to_ws())
    try:
        while True:
            raw = await websocket.receive_text()
            try:
                payload = json.loads(raw)
            except json.JSONDecodeError:
                continue
            payload.setdefault("user_id", str(user_id))
            # Ghost mode: drop the publisher's location frames before any
            # ingestion or fan-out. We still allow chat / typing / arrival
            # frames so the user stays present in the trip.
            if payload.get("type") == "location":
                if await _is_ghost(user_id, trip_id):
                    continue
            # Persist + run side effects (geofence) before fan-out so every
            # subscribed pod sees the same enriched stream.
            try:
                extras = await ingest_frame(
                    trip_id=trip_id, user_id=user_id, frame=payload
                )
            except Exception as exc:  # don't kill the socket on a bad frame
                logger.warning("ingest failed: {}", exc)
                extras = []
            await publish_trip(str(trip_id), json.dumps(payload))
            for extra in extras:
                await publish_trip(str(trip_id), json.dumps(extra))
    except WebSocketDisconnect:
        logger.info("ws disconnected user={} trip={}", user_id, trip_id)
    finally:
        redis_task.cancel()
        await mark_offline(str(trip_id), str(user_id))
        await pubsub.unsubscribe(trip_channel(str(trip_id)))
        await pubsub.aclose()
        await publish_trip(
            str(trip_id),
            json.dumps({"type": "presence", "user_id": str(user_id), "state": "left"}),
        )

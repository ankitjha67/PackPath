"""Read-only live links for non-members.

A trip member mints a short-lived JWT that anyone with the link can
use to fetch a stripped-down view of the trip — last-known member
positions, current waypoints, current ETA. No chat, no PTT, no SOS,
no member identities beyond display names.

The link is opened in any browser via the public route below.
"""

from __future__ import annotations

import time
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from jose import JWTError, jwt
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import get_settings
from ..db import get_session
from ..deps import require_trip_member
from ..models.trip import Trip, TripMember
from ..models.user import User
from ..models.waypoint import Waypoint

router = APIRouter(tags=["livelink"])

_LIVELINK_TTL_HOURS_DEFAULT = 24


class LiveLinkResponse(BaseModel):
    token: str
    expires_at: int
    public_url: str


class LiveLinkMember(BaseModel):
    name: str
    color: str
    lat: float | None
    lng: float | None
    battery: int | None


class LiveLinkWaypoint(BaseModel):
    name: str
    lat: float
    lng: float
    position: int


class LiveLinkSnapshot(BaseModel):
    trip_name: str
    status: str
    members: list[LiveLinkMember]
    waypoints: list[LiveLinkWaypoint]


@router.post(
    "/trips/{trip_id}/livelink",
    response_model=LiveLinkResponse,
)
async def mint_livelink(
    trip_id: uuid.UUID,
    hours: int = Query(default=_LIVELINK_TTL_HOURS_DEFAULT, ge=1, le=168),
    _: TripMember = Depends(require_trip_member),
) -> LiveLinkResponse:
    settings = get_settings()
    now = int(time.time())
    expires = now + hours * 3600
    claims = {
        "iss": "packpath",
        "sub": str(trip_id),
        "type": "livelink",
        "iat": now,
        "exp": expires,
    }
    token = jwt.encode(claims, settings.jwt_secret, algorithm=settings.jwt_algorithm)
    return LiveLinkResponse(
        token=token,
        expires_at=expires,
        public_url=f"/public/livelink/{token}",
    )


_LATEST_LOCATION = """
SELECT DISTINCT ON (l.user_id)
    l.user_id,
    ST_Y(l.geom::geometry) AS lat,
    ST_X(l.geom::geometry) AS lng,
    l.battery_pct
FROM locations l
WHERE l.trip_id = :trip_id
ORDER BY l.user_id, l.recorded_at DESC
"""


@router.get(
    "/public/livelink/{token}",
    response_model=LiveLinkSnapshot,
)
async def read_livelink(
    token: str,
    session: AsyncSession = Depends(get_session),
) -> LiveLinkSnapshot:
    settings = get_settings()
    try:
        claims = jwt.decode(
            token, settings.jwt_secret, algorithms=[settings.jwt_algorithm]
        )
    except JWTError as exc:
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED, "invalid livelink"
        ) from exc
    if claims.get("type") != "livelink":
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "wrong token type")
    trip_id = uuid.UUID(claims["sub"])

    trip = await session.get(Trip, trip_id)
    if trip is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "trip not found")

    members_rows = (
        await session.execute(
            select(TripMember, User.display_name, User.phone)
            .join(User, User.id == TripMember.user_id)
            .where(
                TripMember.trip_id == trip_id, TripMember.left_at.is_(None)
            )
        )
    ).all()
    location_rows = {
        row.user_id: row
        for row in (
            await session.execute(
                _SQL(_LATEST_LOCATION), {"trip_id": trip_id}
            )
        ).all()
    }

    members: list[LiveLinkMember] = []
    for tm, display_name, phone in members_rows:
        if tm.ghost_mode:
            continue
        loc = location_rows.get(tm.user_id)
        members.append(
            LiveLinkMember(
                name=display_name or _mask_phone(phone),
                color=tm.color,
                lat=float(loc.lat) if loc else None,
                lng=float(loc.lng) if loc else None,
                battery=int(loc.battery_pct) if loc and loc.battery_pct else None,
            )
        )

    waypoint_rows = (
        await session.execute(
            select(
                Waypoint.name,
                Waypoint.position,
                func.ST_Y(Waypoint.geom.cast_as("geometry")).label("lat"),
                func.ST_X(Waypoint.geom.cast_as("geometry")).label("lng"),
            )
            .where(Waypoint.trip_id == trip_id)
            .order_by(Waypoint.position.asc())
        )
    ).all()
    waypoints = [
        LiveLinkWaypoint(
            name=row.name,
            lat=float(row.lat),
            lng=float(row.lng),
            position=row.position,
        )
        for row in waypoint_rows
    ]

    return LiveLinkSnapshot(
        trip_name=trip.name,
        status=trip.status,
        members=members,
        waypoints=waypoints,
    )


def _mask_phone(phone: str) -> str:
    if not phone:
        return "Member"
    return f"…{phone[-4:]}"


def _SQL(s: str):
    """Tiny shim so we can pass a raw string to session.execute()."""
    from sqlalchemy import text

    return text(s)

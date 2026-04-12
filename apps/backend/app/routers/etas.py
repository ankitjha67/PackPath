"""Per-member ETA to the next waypoint.

For each active member of the trip we look up their most recent location
in the TimescaleDB hypertable and ask the configured maps provider for
the travel time to the first waypoint (lowest position). Members
without a recent location, or trips without waypoints, are simply
omitted.
"""

from __future__ import annotations

import asyncio
import uuid

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import require_trip_member
from ..models.trip import TripMember
from ..models.waypoint import Waypoint
from ..services.maps import (
    Coordinate,
    MapsProviderError,
    NoRouteFoundError,
    RouteProfile,
)
from ..services.maps.registry import get_directions

router = APIRouter(prefix="/trips/{trip_id}/etas", tags=["etas"])


class MemberEta(BaseModel):
    user_id: uuid.UUID
    distance_m: float
    duration_s: float
    target_waypoint_id: uuid.UUID
    target_waypoint_name: str
    provider: str


class EtaResponse(BaseModel):
    waypoint_id: uuid.UUID | None
    waypoint_name: str | None
    members: list[MemberEta]


_LATEST_LOCATIONS = text(
    """
    SELECT DISTINCT ON (user_id)
        user_id,
        ST_Y(geom::geometry) AS lat,
        ST_X(geom::geometry) AS lng,
        recorded_at
    FROM locations
    WHERE trip_id = :trip_id
    ORDER BY user_id, recorded_at DESC
    """
)


@router.get("", response_model=EtaResponse)
async def get_etas(
    trip_id: uuid.UUID,
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> EtaResponse:
    next_wp = (
        await session.execute(
            select(
                Waypoint.id,
                Waypoint.name,
                func.ST_Y(Waypoint.geom.cast_as("geometry")).label("lat"),
                func.ST_X(Waypoint.geom.cast_as("geometry")).label("lng"),
            )
            .where(Waypoint.trip_id == trip_id)
            .order_by(Waypoint.position.asc())
            .limit(1)
        )
    ).first()
    if next_wp is None:
        return EtaResponse(waypoint_id=None, waypoint_name=None, members=[])

    rows = (
        await session.execute(_LATEST_LOCATIONS, {"trip_id": trip_id})
    ).all()
    if not rows:
        return EtaResponse(
            waypoint_id=next_wp.id, waypoint_name=next_wp.name, members=[]
        )

    target = Coordinate(lat=float(next_wp.lat), lng=float(next_wp.lng))

    async def _one(row) -> MemberEta | None:
        try:
            result = await get_directions(
                [Coordinate(lat=float(row.lat), lng=float(row.lng)), target],
                profile=RouteProfile.DRIVING,
            )
        except (NoRouteFoundError, MapsProviderError):
            return None
        return MemberEta(
            user_id=row.user_id,
            distance_m=result.distance_m,
            duration_s=result.duration_s,
            target_waypoint_id=next_wp.id,
            target_waypoint_name=next_wp.name,
            provider=result.provider,
        )

    # Fan out concurrently — one round trip per member is the long pole.
    results = await asyncio.gather(*[_one(row) for row in rows])
    members = [m for m in results if m is not None]

    return EtaResponse(
        waypoint_id=next_wp.id,
        waypoint_name=next_wp.name,
        members=members,
    )

"""Per-member ETA to the next waypoint.

For each active member of the trip we look up their most recent location
in the TimescaleDB hypertable and ask the Mapbox Directions API for the
travel time to the first waypoint (lowest position). Members without a
recent location, or trips without waypoints, are simply omitted.

This is read-mostly and the value of caching grows fast, so the route is
written so a Redis-backed cache layer can drop in later without changing
the response shape.
"""

from __future__ import annotations

import uuid
from typing import Any

import httpx
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import get_settings
from ..db import get_session
from ..deps import require_trip_member
from ..models.trip import TripMember
from ..models.waypoint import Waypoint

router = APIRouter(prefix="/trips/{trip_id}/etas", tags=["etas"])


class MemberEta(BaseModel):
    user_id: uuid.UUID
    distance_m: float
    duration_s: float
    target_waypoint_id: uuid.UUID
    target_waypoint_name: str


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
    settings = get_settings()
    if not settings.mapbox_server_token:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "MAPBOX_SERVER_TOKEN is not configured",
        )

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

    members: list[MemberEta] = []
    async with httpx.AsyncClient(timeout=10) as client:
        for row in rows:
            try:
                eta = await _ask_mapbox(
                    client=client,
                    token=settings.mapbox_server_token,
                    from_lat=float(row.lat),
                    from_lng=float(row.lng),
                    to_lat=float(next_wp.lat),
                    to_lng=float(next_wp.lng),
                )
            except _DirectionsError:
                continue
            if eta is None:
                continue
            members.append(
                MemberEta(
                    user_id=row.user_id,
                    distance_m=eta["distance"],
                    duration_s=eta["duration"],
                    target_waypoint_id=next_wp.id,
                    target_waypoint_name=next_wp.name,
                )
            )

    return EtaResponse(
        waypoint_id=next_wp.id,
        waypoint_name=next_wp.name,
        members=members,
    )


class _DirectionsError(RuntimeError):
    pass


async def _ask_mapbox(
    *,
    client: httpx.AsyncClient,
    token: str,
    from_lat: float,
    from_lng: float,
    to_lat: float,
    to_lng: float,
) -> dict[str, Any] | None:
    url = (
        "https://api.mapbox.com/directions/v5/mapbox/driving/"
        f"{from_lng},{from_lat};{to_lng},{to_lat}"
    )
    r = await client.get(
        url,
        params={
            "access_token": token,
            "geometries": "geojson",
            "overview": "simplified",
            "alternatives": "false",
        },
    )
    if r.status_code != 200:
        raise _DirectionsError(r.text)
    routes = r.json().get("routes") or []
    if not routes:
        return None
    return {
        "distance": float(routes[0]["distance"]),
        "duration": float(routes[0]["duration"]),
    }

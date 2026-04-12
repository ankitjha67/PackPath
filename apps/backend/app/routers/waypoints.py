from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import require_trip_member
from ..models.trip import TripMember
from ..models.waypoint import Waypoint
from ..schemas.waypoint import WaypointCreate, WaypointOut

router = APIRouter(prefix="/trips/{trip_id}/waypoints", tags=["waypoints"])


def _to_out(wp: Waypoint, lat: float, lng: float) -> WaypointOut:
    return WaypointOut(
        id=wp.id,
        trip_id=wp.trip_id,
        name=wp.name,
        position=wp.position,
        lat=lat,
        lng=lng,
        arrival_radius_m=wp.arrival_radius_m,
        created_at=wp.created_at,
    )


@router.get("", response_model=list[WaypointOut])
async def list_waypoints(
    trip_id: uuid.UUID,
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> list[WaypointOut]:
    rows = (
        await session.execute(
            select(
                Waypoint,
                func.ST_Y(Waypoint.geom.cast_as("geometry")).label("lat"),
                func.ST_X(Waypoint.geom.cast_as("geometry")).label("lng"),
            )
            .where(Waypoint.trip_id == trip_id)
            .order_by(Waypoint.position.asc())
        )
    ).all()
    return [_to_out(wp, lat, lng) for wp, lat, lng in rows]


@router.post("", response_model=WaypointOut, status_code=status.HTTP_201_CREATED)
async def create_waypoint(
    trip_id: uuid.UUID,
    payload: WaypointCreate,
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> WaypointOut:
    wp = Waypoint(
        trip_id=trip_id,
        name=payload.name,
        position=payload.position,
        geom=func.ST_SetSRID(func.ST_MakePoint(payload.lng, payload.lat), 4326),
        arrival_radius_m=payload.arrival_radius_m,
    )
    session.add(wp)
    await session.commit()
    await session.refresh(wp)
    return _to_out(wp, payload.lat, payload.lng)


@router.delete("/{waypoint_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_waypoint(
    trip_id: uuid.UUID,
    waypoint_id: uuid.UUID,
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> None:
    wp = await session.get(Waypoint, waypoint_id)
    if wp is None or wp.trip_id != trip_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "waypoint not found")
    await session.delete(wp)
    await session.commit()

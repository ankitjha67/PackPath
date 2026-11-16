from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, Response, status
from geoalchemy2 import Geometry
from sqlalchemy import cast, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import require_trip_member
from ..models.message import Message
from ..models.trip import TripMember
from ..models.waypoint import Waypoint
from ..schemas.waypoint import WaypointCreate, WaypointOut
from ..services.weather import along_route

router = APIRouter(prefix="/trips/{trip_id}/waypoints", tags=["waypoints"])

_ARRIVAL_PREFIX = "arrived at "


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
                func.ST_Y(cast(Waypoint.geom, Geometry)).label("lat"),
                func.ST_X(cast(Waypoint.geom, Geometry)).label("lng"),
            )
            .where(Waypoint.trip_id == trip_id)
            .order_by(Waypoint.position.asc())
        )
    ).all()
    return [_to_out(wp, lat, lng) for wp, lat, lng in rows]


@router.get("/weather")
async def trip_weather(
    trip_id: uuid.UUID,
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> list[dict]:
    """Weather at each of the trip's waypoints (real via OpenWeather when
    configured, otherwise a deterministic dev mock)."""
    rows = (
        await session.execute(
            select(
                Waypoint,
                func.ST_Y(cast(Waypoint.geom, Geometry)).label("lat"),
                func.ST_X(cast(Waypoint.geom, Geometry)).label("lng"),
            )
            .where(Waypoint.trip_id == trip_id)
            .order_by(Waypoint.position.asc())
        )
    ).all()
    if not rows:
        return []
    coords = [(lat, lng) for _wp, lat, lng in rows]
    # samples == len(coords) makes along_route return one sample per waypoint.
    samples = await along_route(coords, samples=len(coords))
    return [
        {
            "name": wp.name,
            "lat": s.lat,
            "lng": s.lng,
            "temperature_c": round(s.temperature_c, 1),
            "condition": s.condition,
            "wind_kmh": round(s.wind_kmh, 1),
            "pop": s.pop,
        }
        for (wp, _lat, _lng), s in zip(rows, samples)
    ]


@router.get("/progress")
async def waypoint_progress(
    trip_id: uuid.UUID,
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> list[dict]:
    """For each waypoint, who has arrived (from recorded arrival events) and
    when. Lets the marshall see the pack's progress along the route."""
    wp_rows = (
        await session.scalars(
            select(Waypoint)
            .where(Waypoint.trip_id == trip_id)
            .order_by(Waypoint.position.asc())
        )
    ).all()

    # Arrival events are chat messages like "arrived at <name>"; match by name.
    arrivals = (
        await session.scalars(
            select(Message)
            .where(Message.trip_id == trip_id, Message.kind == "arrival")
            .order_by(Message.sent_at.asc())
        )
    ).all()
    # name -> { user_id -> latest arrival time }
    by_name: dict[str, dict[uuid.UUID, str]] = {}
    for a in arrivals:
        if not a.body.startswith(_ARRIVAL_PREFIX):
            continue
        name = a.body[len(_ARRIVAL_PREFIX):]
        by_name.setdefault(name, {})[a.user_id] = a.sent_at.isoformat()

    out: list[dict] = []
    for wp in wp_rows:
        arrived = by_name.get(wp.name, {})
        out.append(
            {
                "waypoint_id": str(wp.id),
                "name": wp.name,
                "position": wp.position,
                "arrived": [
                    {"user_id": str(uid), "at": at}
                    for uid, at in arrived.items()
                ],
            }
        )
    return out


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


@router.delete(
    "/{waypoint_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
    response_model=None,
)
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

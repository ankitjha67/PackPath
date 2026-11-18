from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, Response, status
from geoalchemy2 import Geometry
from pydantic import BaseModel, Field
from sqlalchemy import cast, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import require_trip_member
from ..models.message import Message
from ..models.trip import TripMember
from ..models.waypoint import Waypoint
from ..schemas.waypoint import (
    WaypointCreate,
    WaypointOut,
    WaypointReorder,
    WaypointUpdate,
)
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
        category=wp.category,
        notes=wp.notes,
        assignee_id=wp.assignee_id,
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


class _WxPoint(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)


class WeatherAtRequest(BaseModel):
    points: list[_WxPoint] = Field(max_length=6)


@router.post("/weather/at")
async def weather_at_points(
    trip_id: uuid.UUID,
    payload: WeatherAtRequest,
    _: TripMember = Depends(require_trip_member),
) -> list[dict]:
    """Weather at arbitrary coordinates — used for the live 'route ahead'
    forecast (points projected along the member's heading)."""
    coords = [(p.lat, p.lng) for p in payload.points]
    if not coords:
        return []
    samples = await along_route(coords, samples=len(coords))
    return [
        {
            "lat": s.lat,
            "lng": s.lng,
            "temperature_c": round(s.temperature_c, 1),
            "condition": s.condition,
            "wind_kmh": round(s.wind_kmh, 1),
            "pop": s.pop,
        }
        for s in samples
    ]


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
    await _ensure_route_unlocked(trip_id, _, session)
    wp = Waypoint(
        trip_id=trip_id,
        name=payload.name,
        position=payload.position,
        geom=func.ST_SetSRID(func.ST_MakePoint(payload.lng, payload.lat), 4326),
        arrival_radius_m=payload.arrival_radius_m,
        category=payload.category,
        notes=payload.notes,
    )
    session.add(wp)
    await session.commit()
    await session.refresh(wp)
    return _to_out(wp, payload.lat, payload.lng)


async def _ensure_route_unlocked(
    trip_id: uuid.UUID, member: TripMember, session: AsyncSession
) -> None:
    """Members can't mutate the route while the marshall has it locked; the
    marshall always can."""
    if member.role == "owner":
        return
    from ..models.trip import Trip

    trip = await session.get(Trip, trip_id)
    if trip is not None and trip.route_locked:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, "route is locked by the marshall"
        )


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
    await _ensure_route_unlocked(trip_id, _, session)
    wp = await session.get(Waypoint, waypoint_id)
    if wp is None or wp.trip_id != trip_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "waypoint not found")
    await session.delete(wp)
    await session.commit()


@router.patch("/{waypoint_id}", response_model=WaypointOut)
async def update_waypoint(
    trip_id: uuid.UUID,
    waypoint_id: uuid.UUID,
    payload: WaypointUpdate,
    member: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> WaypointOut:
    """Edit a stop's metadata (name, category, notes, assignee, radius).
    Allowed for any member unless the marshall locked the route."""
    await _ensure_route_unlocked(trip_id, member, session)
    wp = await session.get(Waypoint, waypoint_id)
    if wp is None or wp.trip_id != trip_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "waypoint not found")
    data = payload.model_dump(exclude_unset=True)
    for field in ("name", "category", "notes", "assignee_id", "arrival_radius_m"):
        if field in data:
            setattr(wp, field, data[field])
    await session.commit()
    row = (
        await session.execute(
            select(
                Waypoint,
                func.ST_Y(cast(Waypoint.geom, Geometry)).label("lat"),
                func.ST_X(cast(Waypoint.geom, Geometry)).label("lng"),
            ).where(Waypoint.id == waypoint_id)
        )
    ).one()
    return _to_out(row[0], row[1], row[2])


@router.post("/reorder", response_model=list[WaypointOut])
async def reorder_waypoints(
    trip_id: uuid.UUID,
    payload: WaypointReorder,
    member: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> list[WaypointOut]:
    """Rewrite stop order from a full ordered list of waypoint ids."""
    await _ensure_route_unlocked(trip_id, member, session)
    rows = (
        await session.scalars(
            select(Waypoint).where(Waypoint.trip_id == trip_id)
        )
    ).all()
    by_id = {wp.id: wp for wp in rows}
    if set(payload.order) != set(by_id.keys()):
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "order must list exactly the trip's waypoints",
        )
    for pos, wid in enumerate(payload.order):
        by_id[wid].position = pos
    await session.commit()
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

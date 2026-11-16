"""Pro & integrations (Phase 10): entitlements + route/calendar exports.

- GET /me/entitlements        — effective plan + feature limits
- GET /trips/{id}/export.gpx  — the trip's waypoints + your own track (Pro)
- GET /trips/{id}/trip.ics    — the trip as a calendar event (Pro)
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone
from xml.sax.saxutils import escape

from fastapi import APIRouter, Depends, HTTPException, Response, status
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import current_user, require_trip_member
from ..models.trip import Trip, TripMember
from ..models.user import User
from ..services.entitlements import effective_plan, limits_for

router = APIRouter(tags=["pro"])


class EntitlementsOut(BaseModel):
    plan: str
    max_trip_members: int
    offline_tiles: bool
    route_exports: bool
    advanced_weather: bool
    priority_support: bool


@router.get("/me/entitlements", response_model=EntitlementsOut)
async def my_entitlements(
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> EntitlementsOut:
    plan = await effective_plan(session, user.id)
    limits = limits_for(plan)
    return EntitlementsOut(plan=plan, **limits)


async def _require_pro(session: AsyncSession, user: User) -> None:
    plan = await effective_plan(session, user.id)
    if not limits_for(plan)["route_exports"]:
        raise HTTPException(
            status.HTTP_402_PAYMENT_REQUIRED,
            "Route exports are a Pro feature. Upgrade to export GPX / calendar.",
        )


@router.get("/trips/{trip_id}/export.gpx")
async def export_gpx(
    trip_id: uuid.UUID,
    user: User = Depends(current_user),
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> Response:
    """GPX 1.1 with the trip's waypoints and the caller's own recorded track.
    Importable into Google Earth, Strava, OsmAnd, etc. (Pro)."""
    await _require_pro(session, user)
    trip = await session.get(Trip, trip_id)
    if trip is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "trip not found")

    wpts = (
        await session.execute(
            text(
                """
                SELECT name, ST_Y(geom::geometry) AS lat, ST_X(geom::geometry) AS lng
                FROM waypoints WHERE trip_id = :tid ORDER BY position
                """
            ),
            {"tid": str(trip_id)},
        )
    ).all()
    trk = (
        await session.execute(
            text(
                """
                SELECT ST_Y(geom::geometry) AS lat, ST_X(geom::geometry) AS lng,
                       recorded_at
                FROM locations
                WHERE trip_id = :tid AND user_id = :uid
                ORDER BY recorded_at
                """
            ),
            {"tid": str(trip_id), "uid": str(user.id)},
        )
    ).all()

    parts = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<gpx version="1.1" creator="PackPath" '
        'xmlns="http://www.topografix.com/GPX/1/1">',
        f"  <metadata><name>{escape(trip.name)}</name></metadata>",
    ]
    for w in wpts:
        parts.append(
            f'  <wpt lat="{w.lat:.6f}" lon="{w.lng:.6f}">'
            f"<name>{escape(w.name)}</name></wpt>"
        )
    if trk:
        parts.append(f"  <trk><name>{escape(trip.name)} track</name><trkseg>")
        for p in trk:
            ts = p.recorded_at.astimezone(timezone.utc).strftime(
                "%Y-%m-%dT%H:%M:%SZ"
            )
            parts.append(
                f'    <trkpt lat="{p.lat:.6f}" lon="{p.lng:.6f}">'
                f"<time>{ts}</time></trkpt>"
            )
        parts.append("  </trkseg></trk>")
    parts.append("</gpx>")
    body = "\n".join(parts)

    return Response(
        content=body,
        media_type="application/gpx+xml",
        headers={
            "Content-Disposition": f'attachment; filename="packpath-{trip_id}.gpx"'
        },
    )


def _ics_dt(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


@router.get("/trips/{trip_id}/trip.ics")
async def export_ics(
    trip_id: uuid.UUID,
    user: User = Depends(current_user),
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> Response:
    """The trip as an iCalendar event, importable into any calendar app (Pro)."""
    await _require_pro(session, user)
    trip = await session.get(Trip, trip_id)
    if trip is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "trip not found")

    start = trip.start_at or trip.created_at
    end = trip.end_at or (start + timedelta(hours=3))
    now = datetime.now(tz=timezone.utc)

    def esc(s: str) -> str:
        return s.replace("\\", "\\\\").replace(",", "\\,").replace(";", "\\;")

    lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//PackPath//Trip//EN",
        "BEGIN:VEVENT",
        f"UID:packpath-{trip_id}@packpath.app",
        f"DTSTAMP:{_ics_dt(now)}",
        f"DTSTART:{_ics_dt(start)}",
        f"DTEND:{_ics_dt(end)}",
        f"SUMMARY:{esc(trip.name)}",
        f"DESCRIPTION:{esc('PackPath group trip. Join code: ' + trip.join_code)}",
        "END:VEVENT",
        "END:VCALENDAR",
    ]
    body = "\r\n".join(lines) + "\r\n"
    return Response(
        content=body,
        media_type="text/calendar",
        headers={
            "Content-Disposition": f'attachment; filename="packpath-{trip_id}.ics"'
        },
    )

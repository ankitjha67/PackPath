"""Trip reminders + .ics calendar export."""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Response, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import require_trip_member
from ..models.reminder import Reminder
from ..models.trip import Trip, TripMember

router = APIRouter(prefix="/trips/{trip_id}", tags=["reminders"])


class ReminderCreate(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    body: str | None = None
    fire_at: datetime
    kind: str = Field(default="custom", max_length=20)


class ReminderOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    trip_id: uuid.UUID
    title: str
    body: str | None
    fire_at: datetime
    kind: str
    created_at: datetime
    fired_at: datetime | None


@router.get("/reminders", response_model=list[ReminderOut])
async def list_reminders(
    trip_id: uuid.UUID,
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> list[ReminderOut]:
    rows = (
        await session.scalars(
            select(Reminder)
            .where(Reminder.trip_id == trip_id)
            .order_by(Reminder.fire_at)
        )
    ).all()
    return [ReminderOut.model_validate(r) for r in rows]


@router.post(
    "/reminders",
    response_model=ReminderOut,
    status_code=status.HTTP_201_CREATED,
)
async def create_reminder(
    trip_id: uuid.UUID,
    payload: ReminderCreate,
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> ReminderOut:
    reminder = Reminder(
        trip_id=trip_id,
        title=payload.title,
        body=payload.body,
        fire_at=payload.fire_at,
        kind=payload.kind,
    )
    session.add(reminder)
    await session.commit()
    await session.refresh(reminder)
    return ReminderOut.model_validate(reminder)


# ---------- Calendar export ----------


def _ics_escape(s: str) -> str:
    return (
        s.replace("\\", "\\\\")
        .replace(",", "\\,")
        .replace(";", "\\;")
        .replace("\n", "\\n")
    )


def _ics_dt(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


@router.get("/calendar.ics")
async def calendar_ics(
    trip_id: uuid.UUID,
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> Response:
    trip = await session.get(Trip, trip_id)
    if trip is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "trip not found")
    start = trip.start_at or trip.created_at
    end = trip.end_at or trip.created_at
    reminders = (
        await session.scalars(
            select(Reminder)
            .where(Reminder.trip_id == trip_id)
            .order_by(Reminder.fire_at)
        )
    ).all()

    lines: list[str] = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//PackPath//EN",
        "CALSCALE:GREGORIAN",
        "METHOD:PUBLISH",
        "BEGIN:VEVENT",
        f"UID:trip-{trip.id}@packpath",
        f"DTSTAMP:{_ics_dt(datetime.now(tz=timezone.utc))}",
        f"DTSTART:{_ics_dt(start)}",
        f"DTEND:{_ics_dt(end)}",
        f"SUMMARY:PackPath: {_ics_escape(trip.name)}",
        f"DESCRIPTION:Join code: {trip.join_code}",
        "END:VEVENT",
    ]
    for r in reminders:
        lines.extend(
            [
                "BEGIN:VEVENT",
                f"UID:reminder-{r.id}@packpath",
                f"DTSTAMP:{_ics_dt(datetime.now(tz=timezone.utc))}",
                f"DTSTART:{_ics_dt(r.fire_at)}",
                f"DTEND:{_ics_dt(r.fire_at)}",
                f"SUMMARY:{_ics_escape(r.title)}",
                f"DESCRIPTION:{_ics_escape(r.body or '')}",
                "END:VEVENT",
            ]
        )
    lines.append("END:VCALENDAR")
    body = "\r\n".join(lines) + "\r\n"
    return Response(
        content=body,
        media_type="text/calendar",
        headers={
            "Content-Disposition": f'attachment; filename="trip-{trip.id}.ics"'
        },
    )

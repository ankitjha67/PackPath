from __future__ import annotations

import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Response, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import current_user, require_marshall
from ..models.scheduled import ScheduledAnnouncement
from ..models.trip import TripMember
from ..models.user import User

router = APIRouter(
    prefix="/trips/{trip_id}/scheduled-announcements",
    tags=["scheduled"],
)


class ScheduledCreate(BaseModel):
    body: str = Field(min_length=1, max_length=280)
    send_at: datetime


class ScheduledOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    trip_id: uuid.UUID
    body: str
    send_at: datetime
    sent: bool
    created_at: datetime


@router.get("", response_model=list[ScheduledOut])
async def list_scheduled(
    trip_id: uuid.UUID,
    _: TripMember = Depends(require_marshall),
    session: AsyncSession = Depends(get_session),
) -> list[ScheduledOut]:
    rows = (
        await session.scalars(
            select(ScheduledAnnouncement)
            .where(ScheduledAnnouncement.trip_id == trip_id)
            .order_by(ScheduledAnnouncement.send_at.asc())
        )
    ).all()
    return [ScheduledOut.model_validate(r) for r in rows]


@router.post("", response_model=ScheduledOut, status_code=status.HTTP_201_CREATED)
async def create_scheduled(
    trip_id: uuid.UUID,
    payload: ScheduledCreate,
    user: User = Depends(current_user),
    _: TripMember = Depends(require_marshall),
    session: AsyncSession = Depends(get_session),
) -> ScheduledOut:
    row = ScheduledAnnouncement(
        trip_id=trip_id,
        created_by=user.id,
        body=payload.body,
        send_at=payload.send_at,
    )
    session.add(row)
    await session.commit()
    await session.refresh(row)
    return ScheduledOut.model_validate(row)


@router.delete(
    "/{scheduled_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
    response_model=None,
)
async def cancel_scheduled(
    trip_id: uuid.UUID,
    scheduled_id: uuid.UUID,
    _: TripMember = Depends(require_marshall),
    session: AsyncSession = Depends(get_session),
) -> None:
    row = await session.get(ScheduledAnnouncement, scheduled_id)
    if row is None or row.trip_id != trip_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "not found")
    await session.delete(row)
    await session.commit()

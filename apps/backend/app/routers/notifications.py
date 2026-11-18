"""Push & infra (Phase 9): per-user notification preferences, plus an
owner-only endpoint to exercise the push-targeting pipeline end to end."""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import current_user, require_trip_member
from ..models.notification_pref import NotificationPreferences
from ..models.trip import Trip, TripMember
from ..models.user import User
from ..services.push import eligible_user_ids, push_to_users

router = APIRouter(tags=["notifications"])


class NotificationPrefsOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    enabled: bool
    announcements: bool
    nudges: bool
    detours: bool
    hazards: bool
    chat: bool
    checklist: bool
    quiet_start: int | None
    quiet_end: int | None


class NotificationPrefsUpdate(BaseModel):
    enabled: bool | None = None
    announcements: bool | None = None
    nudges: bool | None = None
    detours: bool | None = None
    hazards: bool | None = None
    chat: bool | None = None
    checklist: bool | None = None
    quiet_start: int | None = Field(default=None, ge=0, le=23)
    quiet_end: int | None = Field(default=None, ge=0, le=23)
    clear_quiet_hours: bool = False


async def _get_or_create(
    session: AsyncSession, user: User
) -> NotificationPreferences:
    prefs = await session.get(NotificationPreferences, user.id)
    if prefs is None:
        prefs = NotificationPreferences(user_id=user.id)
        session.add(prefs)
        await session.commit()
        await session.refresh(prefs)
    return prefs


@router.get("/me/notifications", response_model=NotificationPrefsOut)
async def get_notifications(
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> NotificationPrefsOut:
    return NotificationPrefsOut.model_validate(await _get_or_create(session, user))


@router.patch("/me/notifications", response_model=NotificationPrefsOut)
async def update_notifications(
    payload: NotificationPrefsUpdate,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> NotificationPrefsOut:
    prefs = await _get_or_create(session, user)
    for field in (
        "enabled",
        "announcements",
        "nudges",
        "detours",
        "hazards",
        "chat",
        "checklist",
        "quiet_start",
        "quiet_end",
    ):
        value = getattr(payload, field)
        if value is not None:
            setattr(prefs, field, value)
    if payload.clear_quiet_hours:
        prefs.quiet_start = None
        prefs.quiet_end = None
    prefs.updated_at = datetime.now(tz=timezone.utc)
    await session.commit()
    await session.refresh(prefs)
    return NotificationPrefsOut.model_validate(prefs)


class PushTestResult(BaseModel):
    members: int
    targeted: int
    delivered: int


@router.post("/trips/{trip_id}/push/test", response_model=PushTestResult)
async def push_test(
    trip_id: uuid.UUID,
    user: User = Depends(current_user),
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> PushTestResult:
    """Owner-only. Sends a test 'announcements' push to the pack and reports how
    many members it targeted (after preference + quiet-hour gating) and how many
    devices FCM accepted (0 in dev without FCM). Proves the pipeline wiring."""
    trip = await session.get(Trip, trip_id)
    if trip is None or trip.owner_id != user.id:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, "only the trip owner can send a test push"
        )
    member_ids = (
        await session.scalars(
            select(TripMember.user_id).where(
                TripMember.trip_id == trip_id, TripMember.left_at.is_(None)
            )
        )
    ).all()
    targeted = await eligible_user_ids(session, member_ids, "announcements")
    delivered = await push_to_users(
        session=session,
        user_ids=member_ids,
        category="announcements",
        title="PackPath test",
        body="If you can see this, push is wired up.",
        data={"trip_id": str(trip_id), "test": "1"},
    )
    return PushTestResult(
        members=len(member_ids), targeted=len(targeted), delivered=delivered
    )

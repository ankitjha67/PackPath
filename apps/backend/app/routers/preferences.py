"""Personalization (Phase 8): per-user preferences, synced server-side.

Units, temperature scale, default map style, and vehicle profile follow the
user across devices. The row is created lazily with sensible defaults on first
read, so clients can always GET then PATCH.
"""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import current_user
from ..models.preferences import VEHICLE_TYPES, UserPreferences
from ..models.user import User

router = APIRouter(prefix="/me/preferences", tags=["me"])


class PreferencesOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    units: str
    temp_unit: str
    map_style: str
    vehicle_type: str
    mileage_kmpl: float | None
    share_location_default: bool


class PreferencesUpdate(BaseModel):
    units: str | None = Field(default=None, pattern="^(metric|imperial)$")
    temp_unit: str | None = Field(default=None, pattern="^(c|f)$")
    map_style: str | None = Field(default=None, max_length=20)
    vehicle_type: str | None = None
    mileage_kmpl: float | None = Field(default=None, ge=1, le=100)
    share_location_default: bool | None = None


async def _get_or_create(
    session: AsyncSession, user: User
) -> UserPreferences:
    prefs = await session.get(UserPreferences, user.id)
    if prefs is None:
        prefs = UserPreferences(user_id=user.id)
        session.add(prefs)
        await session.commit()
        await session.refresh(prefs)
    return prefs


@router.get("", response_model=PreferencesOut)
async def get_preferences(
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> PreferencesOut:
    prefs = await _get_or_create(session, user)
    return PreferencesOut.model_validate(prefs)


@router.patch("", response_model=PreferencesOut)
async def update_preferences(
    payload: PreferencesUpdate,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> PreferencesOut:
    prefs = await _get_or_create(session, user)
    if payload.vehicle_type is not None:
        if payload.vehicle_type not in VEHICLE_TYPES:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "invalid vehicle_type")
        prefs.vehicle_type = payload.vehicle_type
    if payload.units is not None:
        prefs.units = payload.units
    if payload.temp_unit is not None:
        prefs.temp_unit = payload.temp_unit
    if payload.map_style is not None:
        prefs.map_style = payload.map_style
    if payload.mileage_kmpl is not None:
        prefs.mileage_kmpl = payload.mileage_kmpl
    if payload.share_location_default is not None:
        prefs.share_location_default = payload.share_location_default
    prefs.updated_at = datetime.now(tz=timezone.utc)
    await session.commit()
    await session.refresh(prefs)
    return PreferencesOut.model_validate(prefs)

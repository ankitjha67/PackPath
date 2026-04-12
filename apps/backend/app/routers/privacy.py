"""Per-member privacy controls + audit log read API."""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import current_user, require_trip_member
from ..models.audit import AuditLog
from ..models.trip import TripMember
from ..models.user import User

router = APIRouter(tags=["privacy"])


class VisibilityScope(BaseModel):
    type: str = Field(pattern="^(all|some|none)$")
    user_ids: list[uuid.UUID] = Field(default_factory=list)


class VisibilityUpdate(BaseModel):
    scope: VisibilityScope


@router.post("/trips/{trip_id}/visibility")
async def set_visibility(
    trip_id: uuid.UUID,
    payload: VisibilityUpdate,
    user: User = Depends(current_user),
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> dict:
    member = await session.scalar(
        select(TripMember).where(
            TripMember.trip_id == trip_id, TripMember.user_id == user.id
        )
    )
    if member is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "member not found")
    member.visibility_scope = payload.scope.model_dump(mode="json")
    await session.commit()
    return {"scope": member.visibility_scope}


class TimeBoxedShare(BaseModel):
    minutes: int = Field(ge=1, le=24 * 60)


@router.post("/trips/{trip_id}/share_for")
async def share_for(
    trip_id: uuid.UUID,
    payload: TimeBoxedShare,
    user: User = Depends(current_user),
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> dict:
    member = await session.scalar(
        select(TripMember).where(
            TripMember.trip_id == trip_id, TripMember.user_id == user.id
        )
    )
    if member is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "member not found")
    member.share_until = datetime.now(tz=timezone.utc) + timedelta(
        minutes=payload.minutes
    )
    member.ghost_mode = False
    await session.commit()
    return {"share_until": member.share_until.isoformat()}


# ---------- Audit log ----------


class AuditEntry(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    actor_user_id: uuid.UUID | None
    trip_id: uuid.UUID | None
    action: str
    details: dict
    created_at: datetime


@router.get("/me/audit", response_model=list[AuditEntry])
async def get_my_audit_log(
    user: User = Depends(current_user),
    limit: int = 100,
    session: AsyncSession = Depends(get_session),
) -> list[AuditEntry]:
    rows = (
        await session.scalars(
            select(AuditLog)
            .where(AuditLog.subject_user_id == user.id)
            .order_by(desc(AuditLog.created_at))
            .limit(limit)
        )
    ).all()
    return [AuditEntry.model_validate(r) for r in rows]

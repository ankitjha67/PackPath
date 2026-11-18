"""Group dynamics — roles, ready-check, sub-groups, trip templates."""

from __future__ import annotations

import uuid
from datetime import datetime

from fastapi import APIRouter, Body, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

import json
import secrets

from ..db import get_session
from ..deps import current_user, require_trip_member
from ..models.subgroup import Subgroup
from ..models.trip import TripMember
from ..models.user import User
from ..redis import publish_trip

router = APIRouter(tags=["group"])


# ---------- Roles ----------

_VALID_ROLES = {
    "owner",
    "member",
    "driver",
    "navigator",
    "dj",
    "photographer",
    "treasurer",
}


class RoleUpdate(BaseModel):
    role: str = Field(...)


@router.post(
    "/trips/{trip_id}/members/{user_id}/role",
    tags=["roles"],
)
async def set_member_role(
    trip_id: uuid.UUID,
    user_id: uuid.UUID,
    payload: RoleUpdate,
    actor: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> dict:
    if payload.role not in _VALID_ROLES:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "invalid role")
    if payload.role == "owner":
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, "owner is set at trip creation"
        )
    target = await session.scalar(
        select(TripMember).where(
            TripMember.trip_id == trip_id, TripMember.user_id == user_id
        )
    )
    if target is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "member not found")
    if target.left_at is not None:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, "member has left the trip"
        )
    # Don't demote the owner — that would leave the trip with zero owners while
    # trips.owner_id still points at them, desyncing owner-gated features.
    if target.role == "owner":
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, "the owner's role cannot be changed"
        )
    actor_member = await session.scalar(
        select(TripMember).where(
            TripMember.trip_id == trip_id, TripMember.user_id == actor.id
        )
    )
    if actor_member is None or actor_member.role != "owner":
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, "only the owner can change roles"
        )
    target.role = payload.role
    await session.commit()
    return {"user_id": str(user_id), "role": payload.role}


# ---------- Member status ----------

_VALID_STATUSES = {"moving", "stopped", "break", "fuel"}


class StatusUpdate(BaseModel):
    status: str = Field(...)


@router.post("/trips/{trip_id}/status")
async def set_member_status(
    trip_id: uuid.UUID,
    payload: StatusUpdate,
    actor: User = Depends(current_user),
    _: TripMember = Depends(require_trip_member),
) -> dict:
    """Broadcast a lightweight, live status ('moving'/'stopped'/'break'/
    'fuel') so the pack sees who's paused. Ephemeral — not persisted."""
    if payload.status not in _VALID_STATUSES:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "invalid status")
    await publish_trip(
        str(trip_id),
        json.dumps(
            {
                "type": "status",
                "user_id": str(actor.id),
                "status": payload.status,
            }
        ),
    )
    return {"status": payload.status}


# ---------- Nudge ----------


class NudgeRequest(BaseModel):
    to_user_id: uuid.UUID


@router.post("/trips/{trip_id}/nudge")
async def nudge_member(
    trip_id: uuid.UUID,
    payload: NudgeRequest,
    actor: User = Depends(current_user),
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """Send a targeted 'catch up' ping to one member of the trip. Delivered
    over the WS fan-out; only the recipient's client reacts to it."""
    target = await session.scalar(
        select(TripMember).where(
            TripMember.trip_id == trip_id,
            TripMember.user_id == payload.to_user_id,
            TripMember.left_at.is_(None),
        )
    )
    if target is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "member not in this trip")
    nudge_id = secrets.token_urlsafe(8)
    await publish_trip(
        str(trip_id),
        json.dumps(
            {
                "type": "nudge",
                "nudge_id": nudge_id,
                "user_id": str(actor.id),
                "to_user_id": str(payload.to_user_id),
                "from_name": actor.display_name or "A teammate",
            }
        ),
    )
    return {"nudge_id": nudge_id}


# ---------- Ready-check ----------


class ReadyCheckMember(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    user_id: uuid.UUID
    is_ready: bool


class ReadyCheckResponse(BaseModel):
    members: list[ReadyCheckMember]
    all_ready: bool


@router.post("/trips/{trip_id}/ready_check", response_model=ReadyCheckResponse)
async def toggle_ready(
    trip_id: uuid.UUID,
    on: bool = Body(..., embed=True),
    user: User = Depends(current_user),
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> ReadyCheckResponse:
    member = await session.scalar(
        select(TripMember).where(
            TripMember.trip_id == trip_id, TripMember.user_id == user.id
        )
    )
    if member is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "member not found")
    member.is_ready = on
    await session.commit()
    state = await _ready_check_state(session, trip_id)
    # Fan out so the marshall's roster updates live without polling.
    await publish_trip(
        str(trip_id),
        json.dumps(
            {
                "type": "ready",
                "user_id": str(user.id),
                "is_ready": on,
                "all_ready": state.all_ready,
            }
        ),
    )
    return state


@router.get("/trips/{trip_id}/ready_check", response_model=ReadyCheckResponse)
async def get_ready_state(
    trip_id: uuid.UUID,
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> ReadyCheckResponse:
    return await _ready_check_state(session, trip_id)


async def _ready_check_state(
    session: AsyncSession, trip_id: uuid.UUID
) -> ReadyCheckResponse:
    members = (
        await session.scalars(
            select(TripMember).where(
                TripMember.trip_id == trip_id, TripMember.left_at.is_(None)
            )
        )
    ).all()
    return ReadyCheckResponse(
        members=[ReadyCheckMember.model_validate(m) for m in members],
        all_ready=all(m.is_ready for m in members) if members else False,
    )


# ---------- Sub-groups ----------


class SubgroupCreate(BaseModel):
    name: str = Field(min_length=1, max_length=60)
    color: str = Field(default="#10B981")


class SubgroupOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    trip_id: uuid.UUID
    name: str
    color: str
    created_at: datetime


@router.get(
    "/trips/{trip_id}/subgroups",
    response_model=list[SubgroupOut],
    tags=["subgroups"],
)
async def list_subgroups(
    trip_id: uuid.UUID,
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> list[SubgroupOut]:
    rows = (
        await session.scalars(
            select(Subgroup).where(Subgroup.trip_id == trip_id)
        )
    ).all()
    return [SubgroupOut.model_validate(r) for r in rows]


@router.post(
    "/trips/{trip_id}/subgroups",
    response_model=SubgroupOut,
    tags=["subgroups"],
    status_code=status.HTTP_201_CREATED,
)
async def create_subgroup(
    trip_id: uuid.UUID,
    payload: SubgroupCreate,
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> SubgroupOut:
    subgroup = Subgroup(trip_id=trip_id, name=payload.name, color=payload.color)
    session.add(subgroup)
    await session.commit()
    await session.refresh(subgroup)
    return SubgroupOut.model_validate(subgroup)


class JoinSubgroup(BaseModel):
    subgroup_id: uuid.UUID | None = None  # null = leave any sub-group


@router.post("/trips/{trip_id}/subgroups/join")
async def join_subgroup(
    trip_id: uuid.UUID,
    payload: JoinSubgroup,
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
    if payload.subgroup_id is not None:
        sg = await session.get(Subgroup, payload.subgroup_id)
        if sg is None or sg.trip_id != trip_id:
            raise HTTPException(
                status.HTTP_404_NOT_FOUND, "subgroup not in this trip"
            )
    member.subgroup_id = payload.subgroup_id
    await session.commit()
    return {"subgroup_id": str(member.subgroup_id) if member.subgroup_id else None}


# ---------- Trip templates ----------


class TripTemplate(BaseModel):
    id: str
    name: str
    description: str
    suggested_radius_km: int
    cover_color: str
    packing_list: list[str]
    reminders_hours_before: list[int]


_TEMPLATES: list[TripTemplate] = [
    TripTemplate(
        id="weekend_road_trip",
        name="Weekend road trip",
        description="2-day getaway with overnight stops.",
        suggested_radius_km=300,
        cover_color="#3B82F6",
        packing_list=[
            "Phone car charger",
            "Power bank",
            "Snacks",
            "First aid kit",
            "Spare tyre check",
        ],
        reminders_hours_before=[24, 1],
    ),
    TripTemplate(
        id="trek_basecamp",
        name="Trek to base camp",
        description="Multi-day high-altitude trek with shared comms.",
        suggested_radius_km=80,
        cover_color="#10B981",
        packing_list=[
            "Headlamp",
            "Layered clothing",
            "Sunscreen",
            "Hydration pack",
            "Offline map cache",
        ],
        reminders_hours_before=[48, 12, 1],
    ),
    TripTemplate(
        id="airport_run",
        name="Airport run",
        description="Pickup or drop with multi-stop pickups.",
        suggested_radius_km=60,
        cover_color="#F97316",
        packing_list=["Boarding pass", "ID", "FASTag balance"],
        reminders_hours_before=[3, 1],
    ),
    TripTemplate(
        id="wedding_convoy",
        name="Wedding convoy",
        description="Long-distance multi-vehicle journey.",
        suggested_radius_km=600,
        cover_color="#EC4899",
        packing_list=[
            "Outfits per event",
            "Gifts",
            "Emergency contact list",
            "Music playlist",
        ],
        reminders_hours_before=[72, 24, 6],
    ),
    TripTemplate(
        id="school_run",
        name="Daily school run",
        description="Recurring short trip with the same passengers.",
        suggested_radius_km=20,
        cover_color="#A855F7",
        packing_list=[],
        reminders_hours_before=[1],
    ),
]


@router.get("/trip_templates", response_model=list[TripTemplate], tags=["templates"])
async def list_trip_templates() -> list[TripTemplate]:
    return _TEMPLATES

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import current_user, require_trip_member
from ..models.trip import Trip, TripMember
from ..models.user import User
from ..schemas.trip import TripCreate, TripJoinRequest, TripMemberOut, TripOut
from ..security import generate_join_code

router = APIRouter(prefix="/trips", tags=["trips"])

_PALETTE = [
    "#3B82F6",
    "#F97316",
    "#10B981",
    "#A855F7",
    "#EF4444",
    "#06B6D4",
    "#FACC15",
    "#EC4899",
]


async def _serialize_trip(trip: Trip, session: AsyncSession) -> TripOut:
    members_rows = (
        await session.scalars(
            select(TripMember).where(
                TripMember.trip_id == trip.id, TripMember.left_at.is_(None)
            )
        )
    ).all()
    return TripOut(
        id=trip.id,
        owner_id=trip.owner_id,
        name=trip.name,
        status=trip.status,
        start_at=trip.start_at,
        end_at=trip.end_at,
        join_code=trip.join_code,
        created_at=trip.created_at,
        members=[TripMemberOut.model_validate(m) for m in members_rows],
    )


_FREE_MAX_DURATION_HOURS = 24
_FREE_MAX_MEMBERS = 5


@router.post("", response_model=TripOut, status_code=status.HTTP_201_CREATED)
async def create_trip(
    payload: TripCreate,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> TripOut:
    # Free-tier guard: a planned window longer than 24h requires Pro.
    # Subscription state will live on a separate table; for now we treat
    # every user as free.
    if payload.start_at and payload.end_at:
        delta = payload.end_at - payload.start_at
        if delta.total_seconds() > _FREE_MAX_DURATION_HOURS * 3600:
            raise HTTPException(
                status.HTTP_402_PAYMENT_REQUIRED,
                "Trips longer than 24 hours require PackPath Pro",
            )
    trip = Trip(
        owner_id=user.id,
        name=payload.name,
        status="planned",
        start_at=payload.start_at,
        end_at=payload.end_at,
        join_code=generate_join_code(),
    )
    session.add(trip)
    await session.flush()
    session.add(
        TripMember(
            trip_id=trip.id,
            user_id=user.id,
            role="owner",
            color=_PALETTE[0],
        )
    )
    await session.commit()
    await session.refresh(trip)
    return await _serialize_trip(trip, session)


@router.get("", response_model=list[TripOut])
async def list_my_trips(
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> list[TripOut]:
    trip_ids = (
        await session.scalars(
            select(TripMember.trip_id).where(
                TripMember.user_id == user.id, TripMember.left_at.is_(None)
            )
        )
    ).all()
    if not trip_ids:
        return []
    trips = (await session.scalars(select(Trip).where(Trip.id.in_(trip_ids)))).all()
    return [await _serialize_trip(t, session) for t in trips]


@router.get("/{trip_id}", response_model=TripOut)
async def get_trip(
    trip_id: uuid.UUID,
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> TripOut:
    trip = await session.get(Trip, trip_id)
    if trip is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "trip not found")
    return await _serialize_trip(trip, session)


@router.post("/join", response_model=TripOut)
async def join_trip(
    payload: TripJoinRequest,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> TripOut:
    trip = await session.scalar(select(Trip).where(Trip.join_code == payload.join_code))
    if trip is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "invalid code")
    if trip.status in ("ended", "cancelled"):
        raise HTTPException(status.HTTP_410_GONE, "trip is over")

    existing = await session.scalar(
        select(TripMember).where(
            TripMember.trip_id == trip.id, TripMember.user_id == user.id
        )
    )
    if existing is None:
        active_count = await session.scalar(
            select(func.count())
            .select_from(TripMember)
            .where(
                TripMember.trip_id == trip.id, TripMember.left_at.is_(None)
            )
        )
        if active_count is not None and active_count >= _FREE_MAX_MEMBERS:
            raise HTTPException(
                status.HTTP_402_PAYMENT_REQUIRED,
                f"Free trips are capped at {_FREE_MAX_MEMBERS} members. Upgrade to Pro for unlimited.",
            )
        used = set(
            (
                await session.scalars(
                    select(TripMember.color).where(TripMember.trip_id == trip.id)
                )
            ).all()
        )
        color = next((c for c in _PALETTE if c not in used), _PALETTE[0])
        session.add(
            TripMember(
                trip_id=trip.id,
                user_id=user.id,
                role="member",
                color=color,
            )
        )
    elif existing.left_at is not None:
        existing.left_at = None
    await session.commit()
    return await _serialize_trip(trip, session)


@router.post("/{trip_id}/leave", status_code=status.HTTP_204_NO_CONTENT)
async def leave_trip(
    trip_id: uuid.UUID,
    member: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> None:
    from datetime import datetime, timezone

    member.left_at = datetime.now(tz=timezone.utc)
    await session.commit()


@router.post("/{trip_id}/ghost", response_model=TripMemberOut)
async def set_ghost_mode(
    trip_id: uuid.UUID,
    on: bool,
    member: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> TripMemberOut:
    """Toggle ghost mode for the requesting member.

    Ghost mode hides this user's location from peers without removing
    them from the trip — they keep seeing everyone else's positions.
    The WS gateway suppresses fan-out of `location` frames where the
    sender is currently in ghost mode.
    """
    member.ghost_mode = on
    await session.commit()
    await session.refresh(member)
    return TripMemberOut.model_validate(member)


@router.post("/{trip_id}/end", response_model=TripOut)
async def end_trip(
    trip_id: uuid.UUID,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> TripOut:
    trip = await session.get(Trip, trip_id)
    if trip is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "trip not found")
    if trip.owner_id != user.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "only owner can end trip")
    trip.status = "ended"
    await session.commit()
    await session.refresh(trip)
    return await _serialize_trip(trip, session)

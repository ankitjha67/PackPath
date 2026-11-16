"""Per-trip contact exchange.

A member may view another member's public profile (name, avatar, bio,
country — never the phone) and request to swap phone numbers. The number is
revealed to both sides only after the target accepts, and only within this
trip. The recipient of a request sees just the requester's name + avatar
until they accept (product decision).
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import and_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import current_user, require_trip_member
from ..models.contact import ContactRequest
from ..models.trip import TripMember
from ..models.user import User

router = APIRouter(prefix="/trips/{trip_id}/contacts", tags=["contacts"])


class MemberProfileOut(BaseModel):
    id: uuid.UUID
    display_name: str | None = None
    avatar_url: str | None = None
    bio: str | None = None
    country: str | None = None
    # Only present once the two are connected in this trip.
    phone: str | None = None
    # none | pending_outgoing | pending_incoming | connected
    connection: str = "none"
    # Set when connection == pending_incoming, so the viewer can accept.
    request_id: uuid.UUID | None = None


class RequesterOut(BaseModel):
    """What a recipient sees about a pending requester: name + avatar only."""

    request_id: uuid.UUID
    requester_id: uuid.UUID
    display_name: str | None = None
    avatar_url: str | None = None
    created_at: datetime


class ContactRequestCreate(BaseModel):
    target_id: uuid.UUID


async def _require_target_member(
    session: AsyncSession, trip_id: uuid.UUID, target_id: uuid.UUID
) -> None:
    is_member = await session.scalar(
        select(TripMember.user_id).where(
            TripMember.trip_id == trip_id,
            TripMember.user_id == target_id,
            TripMember.left_at.is_(None),
        )
    )
    if is_member is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "not a member of this trip")


async def _pair_requests(
    session: AsyncSession,
    trip_id: uuid.UUID,
    a: uuid.UUID,
    b: uuid.UUID,
) -> list[ContactRequest]:
    """All requests between a and b (either direction) in this trip."""
    rows = (
        await session.scalars(
            select(ContactRequest).where(
                ContactRequest.trip_id == trip_id,
                or_(
                    and_(
                        ContactRequest.requester_id == a,
                        ContactRequest.target_id == b,
                    ),
                    and_(
                        ContactRequest.requester_id == b,
                        ContactRequest.target_id == a,
                    ),
                ),
            )
        )
    ).all()
    return list(rows)


@router.get("/members/{user_id}", response_model=MemberProfileOut)
async def get_member_profile(
    trip_id: uuid.UUID,
    user_id: uuid.UUID,
    me: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> MemberProfileOut:
    await _require_target_member(session, trip_id, user_id)
    target = await session.get(User, user_id)
    if target is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "user not found")

    out = MemberProfileOut(
        id=target.id,
        display_name=target.display_name,
        avatar_url=target.avatar_url,
        bio=target.bio,
        country=target.country,
    )
    if user_id == me.user_id:
        # Looking at yourself — show your own number, no connection concept.
        out.phone = target.phone
        return out

    reqs = await _pair_requests(session, trip_id, me.user_id, user_id)
    if any(r.status == "accepted" for r in reqs):
        out.connection = "connected"
        out.phone = target.phone
        return out
    for r in reqs:
        if r.status == "pending" and r.requester_id == me.user_id:
            out.connection = "pending_outgoing"
        elif r.status == "pending" and r.target_id == me.user_id:
            out.connection = "pending_incoming"
            out.request_id = r.id
    return out


@router.post(
    "/requests",
    response_model=MemberProfileOut,
    status_code=status.HTTP_201_CREATED,
)
async def request_contact(
    trip_id: uuid.UUID,
    payload: ContactRequestCreate,
    me: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> MemberProfileOut:
    if payload.target_id == me.user_id:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "cannot request yourself")
    await _require_target_member(session, trip_id, payload.target_id)

    reqs = await _pair_requests(session, trip_id, me.user_id, payload.target_id)
    if any(r.status == "accepted" for r in reqs):
        raise HTTPException(status.HTTP_409_CONFLICT, "already connected")
    # If the other side already asked us, accepting-by-requesting is friendlier
    # than creating a second pending row.
    incoming = next(
        (
            r
            for r in reqs
            if r.status in ("pending", "declined")
            and r.target_id == me.user_id
        ),
        None,
    )
    if incoming is not None:
        incoming.status = "accepted"
        incoming.responded_at = datetime.now(tz=timezone.utc)
    else:
        existing = next(
            (r for r in reqs if r.requester_id == me.user_id), None
        )
        if existing is not None:
            existing.status = "pending"  # re-open a declined/old request
            existing.responded_at = None
        else:
            session.add(
                ContactRequest(
                    trip_id=trip_id,
                    requester_id=me.user_id,
                    target_id=payload.target_id,
                    status="pending",
                )
            )
    await session.commit()
    return await get_member_profile(
        trip_id=trip_id, user_id=payload.target_id, me=me, session=session
    )


@router.post("/requests/{request_id}/accept", response_model=MemberProfileOut)
async def accept_request(
    trip_id: uuid.UUID,
    request_id: uuid.UUID,
    me: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> MemberProfileOut:
    req = await session.get(ContactRequest, request_id)
    if req is None or req.trip_id != trip_id or req.target_id != me.user_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "request not found")
    if req.status == "declined":
        raise HTTPException(status.HTTP_409_CONFLICT, "request already declined")
    req.status = "accepted"
    req.responded_at = datetime.now(tz=timezone.utc)
    await session.commit()
    return await get_member_profile(
        trip_id=trip_id, user_id=req.requester_id, me=me, session=session
    )


@router.post("/requests/{request_id}/decline")
async def decline_request(
    trip_id: uuid.UUID,
    request_id: uuid.UUID,
    me: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> dict[str, str]:
    req = await session.get(ContactRequest, request_id)
    if req is None or req.trip_id != trip_id or req.target_id != me.user_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "request not found")
    req.status = "declined"
    req.responded_at = datetime.now(tz=timezone.utc)
    await session.commit()
    return {"status": "declined"}


@router.get("/requests/incoming", response_model=list[RequesterOut])
async def incoming_requests(
    trip_id: uuid.UUID,
    me: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> list[RequesterOut]:
    rows = (
        await session.scalars(
            select(ContactRequest).where(
                ContactRequest.trip_id == trip_id,
                ContactRequest.target_id == me.user_id,
                ContactRequest.status == "pending",
            )
        )
    ).all()
    if not rows:
        return []
    requesters = {
        u.id: u
        for u in (
            await session.scalars(
                select(User).where(
                    User.id.in_({r.requester_id for r in rows})
                )
            )
        ).all()
    }
    out: list[RequesterOut] = []
    for r in rows:
        u = requesters.get(r.requester_id)
        out.append(
            RequesterOut(
                request_id=r.id,
                requester_id=r.requester_id,
                display_name=u.display_name if u else None,
                avatar_url=u.avatar_url if u else None,
                created_at=r.created_at,
            )
        )
    return out

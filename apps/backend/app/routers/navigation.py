"""Navigation (Phase 5): live member-reported road hazards and group detour
votes.

Both are trip-scoped and fan out over the trip WebSocket so every member sees
a hazard drop or a detour proposal the moment it happens:

- road_hazard            — a new hazard was dropped
- road_hazard_cleared    — a hazard was marked gone
- detour_proposed        — someone proposed rerouting the pack
- detour_vote            — a member voted (with running tally)
- detour_resolved        — the proposal was accepted / rejected / cancelled
"""

from __future__ import annotations

import json
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status
from geoalchemy2 import Geography, Geometry
from pydantic import BaseModel, Field
from sqlalchemy import cast, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import current_user, require_trip_member
from ..models.navigation import (
    ROAD_HAZARD_KINDS,
    ROAD_HAZARD_SEVERITIES,
    DetourProposal,
    DetourVote,
    RoadHazard,
)
from ..models.trip import TripMember
from ..models.user import User
from ..redis import publish_trip

router = APIRouter(prefix="/trips/{trip_id}/navigation", tags=["navigation"])

# A dropped hazard lives this long unless someone clears it sooner.
_DEFAULT_HAZARD_TTL_MIN = 180

_HZ_LAT = func.ST_Y(cast(RoadHazard.geom, Geometry))
_HZ_LNG = func.ST_X(cast(RoadHazard.geom, Geometry))
_DT_LAT = func.ST_Y(cast(DetourProposal.geom, Geometry))
_DT_LNG = func.ST_X(cast(DetourProposal.geom, Geometry))


def _point(lat: float, lng: float):
    return cast(func.ST_SetSRID(func.ST_MakePoint(lng, lat), 4326), Geography)


async def _broadcast(trip_id: uuid.UUID, payload: dict) -> None:
    await publish_trip(str(trip_id), json.dumps(payload))


# ---------------------------------------------------------------- road hazards


class HazardCreate(BaseModel):
    kind: str = Field(default="other")
    severity: str = Field(default="warn")
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    note: str | None = Field(default=None, max_length=400)
    ttl_minutes: int = Field(default=_DEFAULT_HAZARD_TTL_MIN, ge=5, le=1440)


class HazardOut(BaseModel):
    id: uuid.UUID
    trip_id: uuid.UUID
    user_id: uuid.UUID | None
    reporter_name: str | None
    kind: str
    severity: str
    lat: float
    lng: float
    note: str | None
    created_at: datetime
    expires_at: datetime
    cleared_at: datetime | None


def _hazard_out(row) -> HazardOut:
    hz, lat, lng, reporter_name = row
    return HazardOut(
        id=hz.id,
        trip_id=hz.trip_id,
        user_id=hz.user_id,
        reporter_name=reporter_name,
        kind=hz.kind,
        severity=hz.severity,
        lat=lat,
        lng=lng,
        note=hz.note,
        created_at=hz.created_at,
        expires_at=hz.expires_at,
        cleared_at=hz.cleared_at,
    )


def _hazard_select():
    return (
        select(RoadHazard, _HZ_LAT.label("lat"), _HZ_LNG.label("lng"), User.display_name)
        .outerjoin(User, User.id == RoadHazard.user_id)
    )


@router.post(
    "/hazards", response_model=HazardOut, status_code=status.HTTP_201_CREATED
)
async def report_hazard(
    trip_id: uuid.UUID,
    payload: HazardCreate,
    user: User = Depends(current_user),
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> HazardOut:
    if payload.kind not in ROAD_HAZARD_KINDS:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "invalid kind")
    if payload.severity not in ROAD_HAZARD_SEVERITIES:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "invalid severity")
    now = datetime.now(tz=timezone.utc)
    hz = RoadHazard(
        trip_id=trip_id,
        user_id=user.id,
        kind=payload.kind,
        severity=payload.severity,
        geom=func.ST_SetSRID(func.ST_MakePoint(payload.lng, payload.lat), 4326),
        note=payload.note,
        expires_at=now + timedelta(minutes=payload.ttl_minutes),
    )
    session.add(hz)
    await session.commit()
    row = (
        await session.execute(_hazard_select().where(RoadHazard.id == hz.id))
    ).first()
    out = _hazard_out(row)
    await _broadcast(
        trip_id,
        {
            "type": "road_hazard",
            "id": str(out.id),
            "kind": out.kind,
            "severity": out.severity,
            "lat": out.lat,
            "lng": out.lng,
            "note": out.note,
            "reporter_name": out.reporter_name,
            "reporter_id": str(out.user_id) if out.user_id else None,
            "expires_at": out.expires_at.isoformat(),
        },
    )
    return out


@router.get("/hazards", response_model=list[HazardOut])
async def list_hazards(
    trip_id: uuid.UUID,
    include_cleared: bool = Query(default=False),
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> list[HazardOut]:
    """Active (not cleared, not expired) hazards for the trip, newest first.
    Pass include_cleared=true to also see the recently resolved ones."""
    now = datetime.now(tz=timezone.utc)
    stmt = _hazard_select().where(RoadHazard.trip_id == trip_id)
    if not include_cleared:
        stmt = stmt.where(
            RoadHazard.cleared_at.is_(None), RoadHazard.expires_at > now
        )
    stmt = stmt.order_by(RoadHazard.created_at.desc()).limit(200)
    rows = (await session.execute(stmt)).all()
    return [_hazard_out(r) for r in rows]


@router.post("/hazards/{hazard_id}/clear", response_model=HazardOut)
async def clear_hazard(
    trip_id: uuid.UUID,
    hazard_id: uuid.UUID,
    user: User = Depends(current_user),
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> HazardOut:
    """Mark a hazard gone ("all clear"). Fans out so it drops off every map."""
    hz = await session.get(RoadHazard, hazard_id)
    if hz is None or hz.trip_id != trip_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "hazard not found")
    if hz.cleared_at is None:
        hz.cleared_at = datetime.now(tz=timezone.utc)
        hz.cleared_by = user.id
        await session.commit()
    row = (
        await session.execute(_hazard_select().where(RoadHazard.id == hz.id))
    ).first()
    await _broadcast(
        trip_id,
        {
            "type": "road_hazard_cleared",
            "id": str(hazard_id),
            "cleared_by": str(user.id),
            "cleared_by_name": user.display_name,
        },
    )
    return _hazard_out(row)


# -------------------------------------------------------------- detour voting


class DetourCreate(BaseModel):
    label: str = Field(min_length=1, max_length=160)
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    reason: str | None = Field(default=None, max_length=400)
    establishment_id: uuid.UUID | None = None


class VoteCreate(BaseModel):
    choice: str = Field(pattern="^(yes|no)$")


class DetourOut(BaseModel):
    id: uuid.UUID
    trip_id: uuid.UUID
    proposed_by: uuid.UUID | None
    proposer_name: str | None
    label: str
    reason: str | None
    lat: float
    lng: float
    establishment_id: uuid.UUID | None
    created_at: datetime
    resolved_at: datetime | None
    outcome: str | None
    yes: int
    no: int
    my_vote: str | None


async def _tally(
    session: AsyncSession, proposal_ids: list[uuid.UUID]
) -> dict[uuid.UUID, tuple[int, int]]:
    if not proposal_ids:
        return {}
    rows = (
        await session.execute(
            select(
                DetourVote.proposal_id,
                DetourVote.choice,
                func.count(DetourVote.id),
            )
            .where(DetourVote.proposal_id.in_(proposal_ids))
            .group_by(DetourVote.proposal_id, DetourVote.choice)
        )
    ).all()
    out: dict[uuid.UUID, tuple[int, int]] = {}
    for pid, choice, count in rows:
        yes, no = out.get(pid, (0, 0))
        if choice == "yes":
            yes = count
        else:
            no = count
        out[pid] = (yes, no)
    return out


async def _my_votes(
    session: AsyncSession, user_id: uuid.UUID, proposal_ids: list[uuid.UUID]
) -> dict[uuid.UUID, str]:
    if not proposal_ids:
        return {}
    rows = (
        await session.execute(
            select(DetourVote.proposal_id, DetourVote.choice).where(
                DetourVote.user_id == user_id,
                DetourVote.proposal_id.in_(proposal_ids),
            )
        )
    ).all()
    return {pid: choice for pid, choice in rows}


def _detour_out(row, tally, my) -> DetourOut:
    dp, lat, lng, proposer_name = row
    yes, no = tally.get(dp.id, (0, 0))
    return DetourOut(
        id=dp.id,
        trip_id=dp.trip_id,
        proposed_by=dp.proposed_by,
        proposer_name=proposer_name,
        label=dp.label,
        reason=dp.reason,
        lat=lat,
        lng=lng,
        establishment_id=dp.establishment_id,
        created_at=dp.created_at,
        resolved_at=dp.resolved_at,
        outcome=dp.outcome,
        yes=yes,
        no=no,
        my_vote=my.get(dp.id),
    )


def _detour_select():
    return (
        select(
            DetourProposal,
            _DT_LAT.label("lat"),
            _DT_LNG.label("lng"),
            User.display_name,
        )
        .outerjoin(User, User.id == DetourProposal.proposed_by)
    )


@router.post(
    "/detours", response_model=DetourOut, status_code=status.HTTP_201_CREATED
)
async def propose_detour(
    trip_id: uuid.UUID,
    payload: DetourCreate,
    user: User = Depends(current_user),
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> DetourOut:
    dp = DetourProposal(
        trip_id=trip_id,
        proposed_by=user.id,
        label=payload.label.strip(),
        reason=payload.reason,
        geom=func.ST_SetSRID(func.ST_MakePoint(payload.lng, payload.lat), 4326),
        establishment_id=payload.establishment_id,
    )
    session.add(dp)
    await session.commit()
    # Proposer auto-votes yes.
    session.add(DetourVote(proposal_id=dp.id, user_id=user.id, choice="yes"))
    await session.commit()
    row = (
        await session.execute(_detour_select().where(DetourProposal.id == dp.id))
    ).first()
    tally = await _tally(session, [dp.id])
    my = await _my_votes(session, user.id, [dp.id])
    out = _detour_out(row, tally, my)
    await _broadcast(
        trip_id,
        {
            "type": "detour_proposed",
            "id": str(out.id),
            "label": out.label,
            "reason": out.reason,
            "lat": out.lat,
            "lng": out.lng,
            "proposer_name": out.proposer_name,
            "proposer_id": str(out.proposed_by) if out.proposed_by else None,
            "yes": out.yes,
            "no": out.no,
        },
    )
    return out


@router.get("/detours", response_model=list[DetourOut])
async def list_detours(
    trip_id: uuid.UUID,
    include_resolved: bool = Query(default=False),
    user: User = Depends(current_user),
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> list[DetourOut]:
    stmt = _detour_select().where(DetourProposal.trip_id == trip_id)
    if not include_resolved:
        stmt = stmt.where(DetourProposal.outcome.is_(None))
    stmt = stmt.order_by(DetourProposal.created_at.desc()).limit(50)
    rows = (await session.execute(stmt)).all()
    ids = [r[0].id for r in rows]
    tally = await _tally(session, ids)
    my = await _my_votes(session, user.id, ids)
    return [_detour_out(r, tally, my) for r in rows]


@router.post("/detours/{proposal_id}/vote", response_model=DetourOut)
async def vote_detour(
    trip_id: uuid.UUID,
    proposal_id: uuid.UUID,
    payload: VoteCreate,
    user: User = Depends(current_user),
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> DetourOut:
    dp = await session.get(DetourProposal, proposal_id)
    if dp is None or dp.trip_id != trip_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "proposal not found")
    if dp.outcome is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "proposal already resolved")
    existing = await session.scalar(
        select(DetourVote).where(
            DetourVote.proposal_id == proposal_id,
            DetourVote.user_id == user.id,
        )
    )
    if existing is None:
        session.add(
            DetourVote(
                proposal_id=proposal_id, user_id=user.id, choice=payload.choice
            )
        )
    else:
        existing.choice = payload.choice
    await session.commit()
    row = (
        await session.execute(
            _detour_select().where(DetourProposal.id == proposal_id)
        )
    ).first()
    tally = await _tally(session, [proposal_id])
    my = await _my_votes(session, user.id, [proposal_id])
    out = _detour_out(row, tally, my)
    await _broadcast(
        trip_id,
        {
            "type": "detour_vote",
            "id": str(proposal_id),
            "user_id": str(user.id),
            "choice": payload.choice,
            "yes": out.yes,
            "no": out.no,
        },
    )
    return out


@router.post("/detours/{proposal_id}/close", response_model=DetourOut)
async def close_detour(
    trip_id: uuid.UUID,
    proposal_id: uuid.UUID,
    outcome: str = Query(pattern="^(accepted|rejected|cancelled)$"),
    user: User = Depends(current_user),
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> DetourOut:
    """Resolve a proposal. Only the proposer may close their own proposal."""
    dp = await session.get(DetourProposal, proposal_id)
    if dp is None or dp.trip_id != trip_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "proposal not found")
    if dp.proposed_by is not None and dp.proposed_by != user.id:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, "only the proposer can close this"
        )
    if dp.outcome is None:
        dp.outcome = outcome
        dp.resolved_at = datetime.now(tz=timezone.utc)
        await session.commit()
    row = (
        await session.execute(
            _detour_select().where(DetourProposal.id == proposal_id)
        )
    ).first()
    tally = await _tally(session, [proposal_id])
    my = await _my_votes(session, user.id, [proposal_id])
    out = _detour_out(row, tally, my)
    await _broadcast(
        trip_id,
        {
            "type": "detour_resolved",
            "id": str(proposal_id),
            "outcome": out.outcome,
            "label": out.label,
            "lat": out.lat,
            "lng": out.lng,
            "resolved_by_name": user.display_name,
        },
    )
    return out

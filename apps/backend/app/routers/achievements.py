"""Gamification (Phase 7): achievements/badges and the trip leaderboard.

Badge *definitions* live here in code; the user_badges table only records which
codes a user has unlocked (so a badge, once earned, stays earned). Metrics are
computed from real activity — distance, places rated, hazards reported, chat,
checklist, trips — so badges are never hand-waved.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import current_user, require_trip_member
from ..models.badge import UserBadge
from ..models.trip import TripMember
from ..models.user import User

router = APIRouter(tags=["achievements"])


class BadgeDef(BaseModel):
    code: str
    label: str
    description: str
    emoji: str
    metric: str
    goal: float


# The catalog. `metric` keys into the computed metrics dict below.
BADGES: list[BadgeDef] = [
    BadgeDef(code="first_ride", label="First Ride", emoji="🏁", metric="trips_joined",
             goal=1, description="Join your first trip."),
    BadgeDef(code="trailblazer", label="Trailblazer", emoji="🚩", metric="trips_owned",
             goal=1, description="Start a trip of your own."),
    BadgeDef(code="pack_leader", label="Pack Leader", emoji="👑", metric="trips_owned",
             goal=3, description="Lead 3 trips as the organizer."),
    BadgeDef(code="centurion", label="Centurion", emoji="💯", metric="distance_km",
             goal=100, description="Cover 100 km across your trips."),
    BadgeDef(code="road_warrior", label="Road Warrior", emoji="🛣️", metric="distance_km",
             goal=1000, description="Cover 1000 km across your trips."),
    BadgeDef(code="night_rider", label="Night Rider", emoji="🌙", metric="night_frames",
             goal=1, description="Travel between 10 pm and 4 am."),
    BadgeDef(code="critic", label="Critic", emoji="⭐", metric="places_rated",
             goal=1, description="Rate a place along the way."),
    BadgeDef(code="explorer", label="Explorer", emoji="🧭", metric="places_rated",
             goal=5, description="Rate 5 different places."),
    BadgeDef(code="guardian", label="Guardian", emoji="🛡️", metric="hazards_reported",
             goal=3, description="Warn the pack with 3 hazard reports."),
    BadgeDef(code="chatterbox", label="Chatterbox", emoji="💬", metric="messages_sent",
             goal=50, description="Send 50 messages to your packs."),
    BadgeDef(code="quartermaster", label="Quartermaster", emoji="🎒",
             metric="checklist_created", goal=10,
             description="Add 10 items to trip checklists."),
]


class BadgeOut(BaseModel):
    code: str
    label: str
    description: str
    emoji: str
    goal: float
    progress: float
    earned: bool
    earned_at: datetime | None


async def _metrics(session: AsyncSession, uid: uuid.UUID) -> dict[str, float]:
    row = (
        await session.execute(
            text(
                """
                WITH ordered AS (
                  SELECT trip_id, geom, recorded_at,
                         LAG(geom) OVER (PARTITION BY trip_id ORDER BY recorded_at)
                           AS prev_geom
                  FROM locations WHERE user_id = :uid
                )
                SELECT
                  COALESCE(SUM(ST_Distance(prev_geom, geom)), 0)::float AS distance_m,
                  (SELECT COUNT(*) FROM locations
                     WHERE user_id = :uid
                       AND EXTRACT(HOUR FROM recorded_at AT TIME ZONE 'UTC')
                           NOT BETWEEN 4 AND 21)::int AS night_frames
                FROM ordered;
                """
            ),
            {"uid": uid},
        )
    ).first()
    counts = (
        await session.execute(
            text(
                """
                SELECT
                  (SELECT COUNT(*) FROM trip_members WHERE user_id = :uid)::int
                    AS trips_joined,
                  (SELECT COUNT(*) FROM trips WHERE owner_id = :uid)::int
                    AS trips_owned,
                  (SELECT COUNT(*) FROM establishment_ratings WHERE user_id = :uid)::int
                    AS places_rated,
                  (SELECT COUNT(*) FROM road_hazards WHERE user_id = :uid)::int
                    AS hazards_reported,
                  (SELECT COUNT(*) FROM messages WHERE user_id = :uid)::int
                    AS messages_sent,
                  (SELECT COUNT(*) FROM checklist_items WHERE created_by = :uid)::int
                    AS checklist_created
                """
            ),
            {"uid": uid},
        )
    ).first()
    return {
        "distance_km": float(row.distance_m or 0) / 1000.0,
        "night_frames": float(row.night_frames or 0),
        "trips_joined": float(counts.trips_joined or 0),
        "trips_owned": float(counts.trips_owned or 0),
        "places_rated": float(counts.places_rated or 0),
        "hazards_reported": float(counts.hazards_reported or 0),
        "messages_sent": float(counts.messages_sent or 0),
        "checklist_created": float(counts.checklist_created or 0),
    }


@router.get("/me/badges", response_model=list[BadgeOut])
async def my_badges(
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> list[BadgeOut]:
    """Evaluate every badge against the user's real activity, persist any newly
    earned ones, and return the full catalog with earned state + progress."""
    metrics = await _metrics(session, user.id)
    already = {
        b.code: b.earned_at
        for b in (
            await session.scalars(
                select(UserBadge).where(UserBadge.user_id == user.id)
            )
        ).all()
    }
    newly: list[UserBadge] = []
    out: list[BadgeOut] = []
    for b in BADGES:
        value = metrics.get(b.metric, 0.0)
        meets = value >= b.goal
        earned_at = already.get(b.code)
        if meets and earned_at is None:
            badge = UserBadge(user_id=user.id, code=b.code)
            session.add(badge)
            newly.append(badge)
        out.append(
            BadgeOut(
                code=b.code,
                label=b.label,
                description=b.description,
                emoji=b.emoji,
                goal=b.goal,
                progress=min(value, b.goal),
                earned=meets or earned_at is not None,
                earned_at=earned_at,
            )
        )
    if newly:
        await session.commit()
        for badge in newly:
            await session.refresh(badge)
        fresh = {b.code: b.earned_at for b in newly}
        out = [
            o.model_copy(update={"earned_at": fresh.get(o.code, o.earned_at)})
            for o in out
        ]
    return out


class LeaderRow(BaseModel):
    user_id: uuid.UUID
    name: str | None
    avatar_url: str | None
    distance_km: float
    messages: int
    hazards: int
    points: float


@router.get("/trips/{trip_id}/leaderboard", response_model=list[LeaderRow])
async def trip_leaderboard(
    trip_id: uuid.UUID,
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> list[LeaderRow]:
    """Rank this trip's members by a blended score of distance covered, chat
    activity, and hazards reported — all trip-scoped."""
    rows = (
        await session.execute(
            text(
                """
                WITH members AS (
                  SELECT DISTINCT user_id FROM trip_members WHERE trip_id = :tid
                ),
                dist AS (
                  SELECT user_id,
                         COALESCE(SUM(ST_Distance(prev_geom, geom)), 0)::float AS d
                  FROM (
                    SELECT user_id, geom,
                           LAG(geom) OVER (PARTITION BY user_id ORDER BY recorded_at)
                             AS prev_geom
                    FROM locations WHERE trip_id = :tid
                  ) s
                  GROUP BY user_id
                ),
                msg AS (
                  SELECT user_id, COUNT(*)::int AS c FROM messages
                  WHERE trip_id = :tid GROUP BY user_id
                ),
                hz AS (
                  SELECT user_id, COUNT(*)::int AS c FROM road_hazards
                  WHERE trip_id = :tid AND user_id IS NOT NULL GROUP BY user_id
                )
                SELECT m.user_id,
                       u.display_name,
                       u.avatar_url,
                       COALESCE(dist.d, 0)::float AS distance_m,
                       COALESCE(msg.c, 0)::int AS messages,
                       COALESCE(hz.c, 0)::int AS hazards
                FROM members m
                JOIN users u ON u.id = m.user_id
                LEFT JOIN dist ON dist.user_id = m.user_id
                LEFT JOIN msg ON msg.user_id = m.user_id
                LEFT JOIN hz ON hz.user_id = m.user_id
                """
            ),
            {"tid": trip_id},
        )
    ).all()
    out: list[LeaderRow] = []
    for r in rows:
        km = float(r.distance_m or 0) / 1000.0
        points = km + 0.5 * int(r.messages) + 5.0 * int(r.hazards)
        out.append(
            LeaderRow(
                user_id=r.user_id,
                name=r.display_name,
                avatar_url=r.avatar_url,
                distance_km=round(km, 1),
                messages=int(r.messages),
                hazards=int(r.hazards),
                points=round(points, 1),
            )
        )
    out.sort(key=lambda x: x.points, reverse=True)
    return out

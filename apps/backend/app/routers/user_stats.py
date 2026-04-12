"""Personal user stats — the data behind the in-app "Wrapped"-style screen."""

from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import current_user
from ..models.user import User

router = APIRouter(prefix="/me/stats", tags=["me"])


@router.get("")
async def get_my_stats(
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """Lifetime stats: total km driven, top speed, longest single trip,
    favourite hour-of-day, trip count, member-of count.

    All computed in two SQL calls so this stays cheap to render."""
    distance_row = (
        await session.execute(
            text(
                """
                WITH ordered AS (
                  SELECT
                    trip_id,
                    geom,
                    speed_mps,
                    recorded_at,
                    LAG(geom) OVER (PARTITION BY trip_id ORDER BY recorded_at) AS prev_geom
                  FROM locations
                  WHERE user_id = :uid
                ),
                per_trip AS (
                  SELECT
                    trip_id,
                    COALESCE(SUM(ST_Distance(prev_geom, geom)), 0) AS distance_m,
                    COALESCE(MAX(speed_mps), 0) AS top_speed_mps
                  FROM ordered
                  GROUP BY trip_id
                )
                SELECT
                  COALESCE(SUM(distance_m), 0)::float        AS total_distance_m,
                  COALESCE(MAX(distance_m), 0)::float        AS longest_trip_m,
                  COALESCE(MAX(top_speed_mps), 0)::float     AS top_speed_mps,
                  COUNT(*)::int                              AS trips_with_data
                FROM per_trip;
                """
            ),
            {"uid": user.id},
        )
    ).first()

    counts_row = (
        await session.execute(
            text(
                """
                SELECT
                  (SELECT COUNT(*) FROM trips WHERE owner_id = :uid)::int AS trips_owned,
                  (SELECT COUNT(*) FROM trip_members WHERE user_id = :uid)::int AS trips_joined
                """
            ),
            {"uid": user.id},
        )
    ).first()

    hour_rows = (
        await session.execute(
            text(
                """
                SELECT EXTRACT(HOUR FROM recorded_at AT TIME ZONE 'UTC')::int AS hour,
                       COUNT(*) AS frames
                FROM locations
                WHERE user_id = :uid
                GROUP BY hour
                ORDER BY frames DESC
                LIMIT 1;
                """
            ),
            {"uid": user.id},
        )
    ).first()

    distance_km = float(distance_row.total_distance_m or 0) / 1000.0
    longest_km = float(distance_row.longest_trip_m or 0) / 1000.0
    return {
        "user_id": str(user.id),
        "total_distance_km": round(distance_km, 1),
        "longest_trip_km": round(longest_km, 1),
        "top_speed_kmh": round(float(distance_row.top_speed_mps or 0) * 3.6, 1),
        "trips_owned": int(counts_row.trips_owned if counts_row else 0),
        "trips_joined": int(counts_row.trips_joined if counts_row else 0),
        "favorite_hour_utc": int(hour_rows.hour) if hour_rows else None,
        "carbon_kg": round(distance_km * 0.13, 1),
    }

"""Server-side trip recap.

Computes a one-shot summary of a trip from the locations hypertable
and the trip's static metadata. Pure read — no side effects. Designed
to be cheap enough to render on demand from the recap screen.
"""

from __future__ import annotations

import uuid

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

_SQL_PER_USER_DISTANCE = text(
    """
    WITH ordered AS (
      SELECT
        user_id,
        recorded_at,
        geom,
        speed_mps,
        battery_pct,
        LAG(geom) OVER (PARTITION BY user_id ORDER BY recorded_at) AS prev_geom
      FROM locations
      WHERE trip_id = :trip_id
    )
    SELECT
      user_id,
      COALESCE(SUM(ST_Distance(prev_geom, geom)), 0) AS distance_m,
      COALESCE(MAX(speed_mps), 0) AS top_speed_mps,
      COALESCE(AVG(speed_mps), 0) AS avg_speed_mps,
      MIN(recorded_at) AS first_at,
      MAX(recorded_at) AS last_at,
      COUNT(*) AS frames
    FROM ordered
    GROUP BY user_id;
    """
)


_SQL_HOUR_HEATMAP = text(
    """
    SELECT EXTRACT(HOUR FROM recorded_at AT TIME ZONE 'UTC')::int AS hour,
           COUNT(*) AS frames
    FROM locations
    WHERE trip_id = :trip_id
    GROUP BY hour
    ORDER BY hour;
    """
)


_GRAMS_CO2_PER_KM = 130  # average ICE car


async def compute_recap(
    session: AsyncSession, trip_id: uuid.UUID
) -> dict:
    rows = (
        await session.execute(_SQL_PER_USER_DISTANCE, {"trip_id": trip_id})
    ).all()
    members = []
    total_distance_m = 0.0
    top_speed_mps = 0.0
    for row in rows:
        members.append(
            {
                "user_id": str(row.user_id),
                "distance_m": float(row.distance_m or 0),
                "top_speed_mps": float(row.top_speed_mps or 0),
                "avg_speed_mps": float(row.avg_speed_mps or 0),
                "frames": int(row.frames),
                "first_at": row.first_at.isoformat() if row.first_at else None,
                "last_at": row.last_at.isoformat() if row.last_at else None,
            }
        )
        total_distance_m += float(row.distance_m or 0)
        if (row.top_speed_mps or 0) > top_speed_mps:
            top_speed_mps = float(row.top_speed_mps)

    heatmap_rows = (
        await session.execute(_SQL_HOUR_HEATMAP, {"trip_id": trip_id})
    ).all()
    heatmap = {int(r.hour): int(r.frames) for r in heatmap_rows}

    distance_km = total_distance_m / 1000.0
    return {
        "trip_id": str(trip_id),
        "total_distance_m": round(total_distance_m, 1),
        "total_distance_km": round(distance_km, 2),
        "top_speed_kmh": round(top_speed_mps * 3.6, 1),
        "members": members,
        "hour_heatmap": heatmap,
        "carbon_kg": round(distance_km * _GRAMS_CO2_PER_KM / 1000.0, 2),
    }

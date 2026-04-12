"""Operational analytics for the team running PackPath.

Every endpoint is read-only over TimescaleDB. The router is gated by
`require_admin` so only users with `users.is_admin = true` can read
operational metrics.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import current_user, require_admin
from ..models.user import User

router = APIRouter(
    prefix="/admin/analytics",
    tags=["admin-analytics"],
    dependencies=[Depends(require_admin)],
)


class HistogramBucket(BaseModel):
    bucket: str  # ISO timestamp truncated to the bucket
    value: float


def _hours_ago(hours: int) -> datetime:
    return datetime.now(tz=timezone.utc) - timedelta(hours=hours)


@router.get("/battery_drain")
async def battery_drain(
    hours: int = Query(default=24, ge=1, le=24 * 30),
    _: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> list[HistogramBucket]:
    """Hourly average battery drain across all devices, in percentage
    points per hour. Negative numbers mean the device was charging."""
    rows = (
        await session.execute(
            text(
                """
                WITH per_user AS (
                  SELECT
                    user_id,
                    time_bucket('1 hour', recorded_at) AS bucket,
                    MAX(battery_pct) - MIN(battery_pct) AS drain
                  FROM locations
                  WHERE recorded_at > :cutoff
                    AND battery_pct IS NOT NULL
                  GROUP BY user_id, bucket
                )
                SELECT bucket, AVG(drain)::float AS avg_drain
                FROM per_user
                GROUP BY bucket
                ORDER BY bucket;
                """
            ),
            {"cutoff": _hours_ago(hours)},
        )
    ).all()
    return [
        HistogramBucket(bucket=row.bucket.isoformat(), value=float(row.avg_drain or 0))
        for row in rows
    ]


@router.get("/maps_provider_health")
async def maps_provider_health(
    hours: int = Query(default=24, ge=1, le=24 * 30),
    _: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> list[dict]:
    rows = (
        await session.execute(
            text(
                """
                SELECT
                  provider,
                  COUNT(*)              AS calls,
                  AVG(duration_ms)::int AS avg_ms,
                  percentile_cont(0.95) WITHIN GROUP (ORDER BY duration_ms)::int AS p95_ms,
                  SUM(CASE WHEN status >= 400 THEN 1 ELSE 0 END)::int AS errors
                FROM maps_provider_calls
                WHERE created_at > :cutoff
                GROUP BY provider
                ORDER BY calls DESC;
                """
            ),
            {"cutoff": _hours_ago(hours)},
        )
    ).all()
    return [
        {
            "provider": row.provider,
            "calls": int(row.calls),
            "avg_ms": int(row.avg_ms or 0),
            "p95_ms": int(row.p95_ms or 0),
            "errors": int(row.errors),
            "error_rate": (
                round(int(row.errors) / int(row.calls), 4)
                if int(row.calls) > 0
                else 0
            ),
        }
        for row in rows
    ]


@router.get("/eta_accuracy")
async def eta_accuracy(
    hours: int = Query(default=24 * 7, ge=1, le=24 * 90),
    _: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """Tracks how close our predicted ETA was to the actual arrival time
    for each waypoint. Computed as the median absolute error in seconds.

    For v1.1 we approximate predicted ETA as the most recent server-side
    ETA computation logged via the `events` table. If no ETA logs exist
    yet (the mobile client hasn't pushed any), the response is a 0-row
    placeholder rather than an error.
    """
    rows = (
        await session.execute(
            text(
                """
                WITH arrivals AS (
                  SELECT
                    (properties->>'waypoint_id')::uuid AS waypoint_id,
                    user_id,
                    created_at
                  FROM events
                  WHERE name = 'arrival_observed'
                    AND created_at > :cutoff
                ),
                predictions AS (
                  SELECT
                    (properties->>'waypoint_id')::uuid AS waypoint_id,
                    user_id,
                    created_at AS predicted_at,
                    (properties->>'eta_seconds')::int  AS eta_seconds,
                    properties->>'provider'            AS provider
                  FROM events
                  WHERE name = 'eta_predicted'
                    AND created_at > :cutoff
                ),
                pairs AS (
                  SELECT
                    p.provider,
                    EXTRACT(EPOCH FROM (a.created_at - p.predicted_at))::int AS actual,
                    p.eta_seconds AS predicted
                  FROM arrivals a
                  JOIN predictions p
                    ON p.waypoint_id = a.waypoint_id
                   AND p.user_id     = a.user_id
                   AND p.predicted_at < a.created_at
                )
                SELECT
                  provider,
                  COUNT(*) AS samples,
                  percentile_cont(0.5) WITHIN GROUP (ORDER BY ABS(actual - predicted))::int AS median_abs_error_s
                FROM pairs
                GROUP BY provider
                ORDER BY samples DESC;
                """
            ),
            {"cutoff": _hours_ago(hours)},
        )
    ).all()
    return {
        "providers": [
            {
                "provider": row.provider,
                "samples": int(row.samples),
                "median_abs_error_s": int(row.median_abs_error_s or 0),
            }
            for row in rows
        ]
    }


@router.get("/ws_lifetimes")
async def ws_lifetimes(
    hours: int = Query(default=24, ge=1, le=24 * 30),
    _: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> dict:
    rows = (
        await session.execute(
            text(
                """
                WITH sessions AS (
                  SELECT
                    user_id,
                    (properties->>'duration_s')::int AS duration_s
                  FROM events
                  WHERE name = 'ws_session_ended'
                    AND created_at > :cutoff
                )
                SELECT
                  COUNT(*)::int AS sessions,
                  percentile_cont(0.5) WITHIN GROUP (ORDER BY duration_s)::int AS p50,
                  percentile_cont(0.95) WITHIN GROUP (ORDER BY duration_s)::int AS p95,
                  percentile_cont(0.99) WITHIN GROUP (ORDER BY duration_s)::int AS p99
                FROM sessions;
                """
            ),
            {"cutoff": _hours_ago(hours)},
        )
    ).all()
    if not rows:
        return {"sessions": 0, "p50": 0, "p95": 0, "p99": 0}
    row = rows[0]
    return {
        "sessions": int(row.sessions or 0),
        "p50": int(row.p50 or 0),
        "p95": int(row.p95 or 0),
        "p99": int(row.p99 or 0),
    }

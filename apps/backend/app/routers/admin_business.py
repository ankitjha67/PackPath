"""Business analytics — MRR, conversion funnel, churn."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Query
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import current_user, require_admin
from ..models.user import User

router = APIRouter(
    prefix="/admin/business",
    tags=["admin-business"],
    dependencies=[Depends(require_admin)],
)


def _days_ago(days: int) -> datetime:
    return datetime.now(tz=timezone.utc) - timedelta(days=days)


@router.get("/mrr")
async def mrr(
    days: int = Query(default=30, ge=1, le=365),
    _: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> dict:
    rows = (
        await session.execute(
            text(
                """
                SELECT
                  plan,
                  COUNT(*)::int AS active,
                  COALESCE(SUM(monthly_amount_cents), 0)::bigint AS mrr_cents
                FROM subscriptions
                WHERE status IN ('trialing','active','past_due')
                  AND started_at > :cutoff
                GROUP BY plan;
                """
            ),
            {"cutoff": _days_ago(days)},
        )
    ).all()
    total_mrr = sum(int(r.mrr_cents) for r in rows)
    return {
        "total_mrr_cents": total_mrr,
        "by_plan": [
            {
                "plan": r.plan,
                "active": int(r.active),
                "mrr_cents": int(r.mrr_cents),
            }
            for r in rows
        ],
    }


@router.get("/funnel")
async def funnel(
    days: int = Query(default=30, ge=1, le=365),
    _: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """Conversion funnel by paywall surface (which 402 caused the upgrade)."""
    rows = (
        await session.execute(
            text(
                """
                SELECT
                  COALESCE(paywall_source, 'unknown')        AS source,
                  COUNT(*)::int                              AS upgrades,
                  COALESCE(SUM(monthly_amount_cents), 0)::bigint AS mrr_cents
                FROM subscriptions
                WHERE plan IN ('pro','family')
                  AND started_at > :cutoff
                GROUP BY source
                ORDER BY upgrades DESC;
                """
            ),
            {"cutoff": _days_ago(days)},
        )
    ).all()
    return {
        "sources": [
            {
                "source": r.source,
                "upgrades": int(r.upgrades),
                "mrr_cents": int(r.mrr_cents),
            }
            for r in rows
        ]
    }


@router.get("/churn")
async def churn(
    days: int = Query(default=30, ge=1, le=365),
    _: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> dict:
    cancelled = (
        await session.scalar(
            text(
                "SELECT COUNT(*)::int FROM subscriptions "
                "WHERE cancelled_at IS NOT NULL AND cancelled_at > :cutoff"
            ),
            {"cutoff": _days_ago(days)},
        )
    ) or 0
    active = (
        await session.scalar(
            text(
                "SELECT COUNT(*)::int FROM subscriptions "
                "WHERE status IN ('trialing','active','past_due')"
            )
        )
    ) or 0
    return {
        "window_days": days,
        "cancelled": int(cancelled),
        "active": int(active),
        "rate": round(cancelled / active, 4) if active else 0,
    }

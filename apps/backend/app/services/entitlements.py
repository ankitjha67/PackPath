"""Pro entitlements (Phase 10).

The effective plan is the richest *active* subscription a user holds (family >
pro > free). Paid plans only count once a verified provider webhook has flipped
them to 'active' (see routers/billing.py), so this can never be self-granted.
"""

from __future__ import annotations

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..models.subscription import Subscription

PLAN_RANK = {"free": 0, "pro": 1, "family": 2}

# Feature limits per plan. Keep flat + serializable so the client can gate UI
# off the same numbers the server enforces.
PLAN_LIMITS: dict[str, dict] = {
    "free": {
        "max_trip_members": 5,
        "offline_tiles": False,
        "route_exports": False,
        "advanced_weather": False,
        "priority_support": False,
    },
    "pro": {
        "max_trip_members": 50,
        "offline_tiles": True,
        "route_exports": True,
        "advanced_weather": True,
        "priority_support": False,
    },
    "family": {
        "max_trip_members": 100,
        "offline_tiles": True,
        "route_exports": True,
        "advanced_weather": True,
        "priority_support": True,
    },
}


async def effective_plan(session: AsyncSession, user_id: uuid.UUID) -> str:
    """The richest active plan the user holds, or 'free'."""
    rows = (
        await session.scalars(
            select(Subscription.plan).where(
                Subscription.user_id == user_id,
                Subscription.status == "active",
            )
        )
    ).all()
    best = "free"
    for plan in rows:
        if PLAN_RANK.get(plan, 0) > PLAN_RANK.get(best, 0):
            best = plan
    return best


def limits_for(plan: str) -> dict:
    return PLAN_LIMITS.get(plan, PLAN_LIMITS["free"])

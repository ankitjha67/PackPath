"""Subscription create / list endpoints.

The actual Razorpay/Stripe webhooks land in v1.2 — this router lets the
mobile app create a subscription stub immediately so we have data to
report on. The `paywall_source` field captures which 402 surface
triggered the upgrade so the funnel report has signal.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import current_user
from ..models.subscription import Subscription
from ..models.user import User

router = APIRouter(prefix="/me/subscriptions", tags=["billing"])

_PLAN_PRICE_CENTS = {
    "free": 0,
    "pro": 14900,  # ₹149
    "family": 29900,  # ₹299
}


class SubscriptionCreate(BaseModel):
    provider: str = Field(pattern="^(razorpay|stripe)$")
    plan: str = Field(pattern="^(free|pro|family)$")
    paywall_source: str | None = None
    currency: str = Field(default="INR", min_length=3, max_length=3)


class SubscriptionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    user_id: uuid.UUID
    provider: str
    plan: str
    status: str
    monthly_amount_cents: int
    currency: str
    paywall_source: str | None
    started_at: datetime
    renewed_at: datetime | None
    cancelled_at: datetime | None


@router.post(
    "", response_model=SubscriptionOut, status_code=status.HTTP_201_CREATED
)
async def create_subscription(
    payload: SubscriptionCreate,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> SubscriptionOut:
    sub = Subscription(
        user_id=user.id,
        provider=payload.provider,
        plan=payload.plan,
        status="trialing" if payload.plan != "free" else "active",
        monthly_amount_cents=_PLAN_PRICE_CENTS.get(payload.plan, 0),
        currency=payload.currency,
        paywall_source=payload.paywall_source,
    )
    session.add(sub)
    await session.commit()
    await session.refresh(sub)
    return SubscriptionOut.model_validate(sub)


@router.get("", response_model=list[SubscriptionOut])
async def list_subscriptions(
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> list[SubscriptionOut]:
    rows = (
        await session.scalars(
            select(Subscription)
            .where(Subscription.user_id == user.id)
            .order_by(desc(Subscription.started_at))
        )
    ).all()
    return [SubscriptionOut.model_validate(r) for r in rows]

"""Trip expenses + cost split.

Each expense is paid by exactly one member and split across an explicit
list of beneficiaries. The /balances endpoint computes net positions per
member: positive = owed by the pack, negative = owes the pack. We use
integer cents throughout to avoid float drift.
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import current_user, require_trip_member
from ..models.expense import Expense, ExpenseShare
from ..models.trip import TripMember
from ..models.user import User

router = APIRouter(prefix="/trips/{trip_id}/expenses", tags=["expenses"])


class ExpenseShareIn(BaseModel):
    user_id: uuid.UUID
    share_cents: int = Field(ge=0)


class ExpenseCreate(BaseModel):
    description: str = Field(min_length=1, max_length=200)
    amount_cents: int = Field(gt=0)
    currency: str = Field(default="INR", min_length=3, max_length=3)
    category: str = Field(default="other", max_length=20)
    # If `shares` is empty we split equally across all active members.
    shares: list[ExpenseShareIn] = Field(default_factory=list)


class ExpenseOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    trip_id: uuid.UUID
    paid_by: uuid.UUID
    description: str
    amount_cents: int
    currency: str
    category: str
    created_at: datetime
    shares: list[ExpenseShareIn]


class Balance(BaseModel):
    user_id: uuid.UUID
    net_cents: int  # positive = pack owes them, negative = they owe pack


class BalancesResponse(BaseModel):
    currency: str
    balances: list[Balance]
    total_spent_cents: int


@router.get("", response_model=list[ExpenseOut])
async def list_expenses(
    trip_id: uuid.UUID,
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> list[ExpenseOut]:
    rows = (
        await session.scalars(
            select(Expense).where(Expense.trip_id == trip_id).order_by(Expense.created_at)
        )
    ).all()
    out: list[ExpenseOut] = []
    for e in rows:
        share_rows = (
            await session.scalars(
                select(ExpenseShare).where(ExpenseShare.expense_id == e.id)
            )
        ).all()
        out.append(
            ExpenseOut(
                id=e.id,
                trip_id=e.trip_id,
                paid_by=e.paid_by,
                description=e.description,
                amount_cents=e.amount_cents,
                currency=e.currency,
                category=e.category,
                created_at=e.created_at,
                shares=[
                    ExpenseShareIn(user_id=s.user_id, share_cents=s.share_cents)
                    for s in share_rows
                ],
            )
        )
    return out


@router.post("", response_model=ExpenseOut, status_code=status.HTTP_201_CREATED)
async def create_expense(
    trip_id: uuid.UUID,
    payload: ExpenseCreate,
    user: User = Depends(current_user),
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> ExpenseOut:
    expense = Expense(
        trip_id=trip_id,
        paid_by=user.id,
        description=payload.description,
        amount_cents=payload.amount_cents,
        currency=payload.currency,
        category=payload.category,
    )
    session.add(expense)
    await session.flush()

    if payload.shares:
        total_share = sum(s.share_cents for s in payload.shares)
        if total_share != payload.amount_cents:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                f"shares ({total_share}c) must sum to amount ({payload.amount_cents}c)",
            )
        shares = list(payload.shares)
    else:
        members = (
            await session.scalars(
                select(TripMember.user_id).where(
                    TripMember.trip_id == trip_id,
                    TripMember.left_at.is_(None),
                )
            )
        ).all()
        if not members:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "no active members")
        per = payload.amount_cents // len(members)
        remainder = payload.amount_cents - per * len(members)
        shares = [
            ExpenseShareIn(
                user_id=uid,
                share_cents=per + (1 if i < remainder else 0),
            )
            for i, uid in enumerate(members)
        ]

    for s in shares:
        session.add(
            ExpenseShare(
                expense_id=expense.id,
                user_id=s.user_id,
                share_cents=s.share_cents,
            )
        )
    await session.commit()
    await session.refresh(expense)
    return ExpenseOut(
        id=expense.id,
        trip_id=expense.trip_id,
        paid_by=expense.paid_by,
        description=expense.description,
        amount_cents=expense.amount_cents,
        currency=expense.currency,
        category=expense.category,
        created_at=expense.created_at,
        shares=shares,
    )


@router.get("/balances", response_model=BalancesResponse)
async def balances(
    trip_id: uuid.UUID,
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> BalancesResponse:
    expenses = (
        await session.scalars(
            select(Expense).where(Expense.trip_id == trip_id)
        )
    ).all()
    if not expenses:
        return BalancesResponse(currency="INR", balances=[], total_spent_cents=0)
    net: dict[uuid.UUID, int] = defaultdict(int)
    total = 0
    currency = expenses[0].currency
    for expense in expenses:
        total += expense.amount_cents
        net[expense.paid_by] += expense.amount_cents
        share_rows = (
            await session.scalars(
                select(ExpenseShare).where(ExpenseShare.expense_id == expense.id)
            )
        ).all()
        for share in share_rows:
            net[share.user_id] -= share.share_cents
    return BalancesResponse(
        currency=currency,
        balances=[Balance(user_id=uid, net_cents=cents) for uid, cents in net.items()],
        total_spent_cents=total,
    )

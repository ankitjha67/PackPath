"""Logistics (Phase 6): the shared, live trip checklist.

Every member sees the same list of things to pack / buy / do. Items can be
claimed ("I've got it"), reassigned, and checked off, and each change fans out
over the trip WebSocket so the list stays in sync without a refresh:

- checklist_added    — a new item
- checklist_updated  — claim / unclaim / done toggle / edit
- checklist_removed  — an item was deleted
"""

from __future__ import annotations

import json
import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Response, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from ..db import get_session
from ..deps import current_user, require_trip_member
from ..models.checklist import CHECKLIST_CATEGORIES, ChecklistItem
from ..models.trip import TripMember
from ..models.user import User
from ..redis import publish_trip

router = APIRouter(prefix="/trips/{trip_id}/checklist", tags=["checklist"])


class ChecklistCreate(BaseModel):
    title: str = Field(min_length=1, max_length=160)
    category: str = Field(default="packing")
    qty: int = Field(default=1, ge=1, le=999)
    assign_to_me: bool = False


class ChecklistUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=160)
    category: str | None = None
    qty: int | None = Field(default=None, ge=1, le=999)


class ChecklistOut(BaseModel):
    id: uuid.UUID
    trip_id: uuid.UUID
    title: str
    category: str
    qty: int
    created_by: uuid.UUID | None
    assigned_to: uuid.UUID | None
    assignee_name: str | None
    done: bool
    done_by: uuid.UUID | None
    created_at: datetime


def _out(item: ChecklistItem, assignee_name: str | None) -> ChecklistOut:
    return ChecklistOut(
        id=item.id,
        trip_id=item.trip_id,
        title=item.title,
        category=item.category,
        qty=item.qty,
        created_by=item.created_by,
        assigned_to=item.assigned_to,
        assignee_name=assignee_name,
        done=item.done,
        done_by=item.done_by,
        created_at=item.created_at,
    )


async def _load(session: AsyncSession, item_id: uuid.UUID) -> ChecklistOut | None:
    assignee = aliased(User)
    row = (
        await session.execute(
            select(ChecklistItem, assignee.display_name)
            .outerjoin(assignee, assignee.id == ChecklistItem.assigned_to)
            .where(ChecklistItem.id == item_id)
        )
    ).first()
    if row is None:
        return None
    return _out(row[0], row[1])


async def _broadcast(trip_id: uuid.UUID, event: str, out: ChecklistOut) -> None:
    await publish_trip(
        str(trip_id),
        json.dumps(
            {
                "type": event,
                "id": str(out.id),
                "title": out.title,
                "category": out.category,
                "qty": out.qty,
                "assigned_to": str(out.assigned_to) if out.assigned_to else None,
                "assignee_name": out.assignee_name,
                "done": out.done,
            }
        ),
    )


@router.get("", response_model=list[ChecklistOut])
async def list_items(
    trip_id: uuid.UUID,
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> list[ChecklistOut]:
    assignee = aliased(User)
    rows = (
        await session.execute(
            select(ChecklistItem, assignee.display_name)
            .outerjoin(assignee, assignee.id == ChecklistItem.assigned_to)
            .where(ChecklistItem.trip_id == trip_id)
            .order_by(ChecklistItem.done.asc(), ChecklistItem.created_at.asc())
        )
    ).all()
    return [_out(item, name) for item, name in rows]


@router.post("", response_model=ChecklistOut, status_code=status.HTTP_201_CREATED)
async def add_item(
    trip_id: uuid.UUID,
    payload: ChecklistCreate,
    user: User = Depends(current_user),
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> ChecklistOut:
    if payload.category not in CHECKLIST_CATEGORIES:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "invalid category")
    item = ChecklistItem(
        trip_id=trip_id,
        title=payload.title.strip(),
        category=payload.category,
        qty=payload.qty,
        created_by=user.id,
        assigned_to=user.id if payload.assign_to_me else None,
    )
    session.add(item)
    await session.commit()
    out = await _load(session, item.id)
    assert out is not None
    await _broadcast(trip_id, "checklist_added", out)
    return out


@router.patch("/{item_id}", response_model=ChecklistOut)
async def edit_item(
    trip_id: uuid.UUID,
    item_id: uuid.UUID,
    payload: ChecklistUpdate,
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> ChecklistOut:
    item = await session.get(ChecklistItem, item_id)
    if item is None or item.trip_id != trip_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "item not found")
    if payload.category is not None:
        if payload.category not in CHECKLIST_CATEGORIES:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "invalid category")
        item.category = payload.category
    if payload.title is not None:
        item.title = payload.title.strip()
    if payload.qty is not None:
        item.qty = payload.qty
    await session.commit()
    out = await _load(session, item.id)
    assert out is not None
    await _broadcast(trip_id, "checklist_updated", out)
    return out


@router.post("/{item_id}/claim", response_model=ChecklistOut)
async def claim_item(
    trip_id: uuid.UUID,
    item_id: uuid.UUID,
    user: User = Depends(current_user),
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> ChecklistOut:
    """Toggle responsibility: claim an unclaimed item for myself, or release
    it if I already hold it."""
    item = await session.get(ChecklistItem, item_id)
    if item is None or item.trip_id != trip_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "item not found")
    item.assigned_to = None if item.assigned_to == user.id else user.id
    await session.commit()
    out = await _load(session, item.id)
    assert out is not None
    await _broadcast(trip_id, "checklist_updated", out)
    return out


@router.post("/{item_id}/toggle", response_model=ChecklistOut)
async def toggle_item(
    trip_id: uuid.UUID,
    item_id: uuid.UUID,
    user: User = Depends(current_user),
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> ChecklistOut:
    """Flip the done state. Records who checked it off."""
    item = await session.get(ChecklistItem, item_id)
    if item is None or item.trip_id != trip_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "item not found")
    item.done = not item.done
    item.done_by = user.id if item.done else None
    await session.commit()
    out = await _load(session, item.id)
    assert out is not None
    await _broadcast(trip_id, "checklist_updated", out)
    return out


@router.delete(
    "/{item_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
    response_model=None,
)
async def delete_item(
    trip_id: uuid.UUID,
    item_id: uuid.UUID,
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> None:
    item = await session.get(ChecklistItem, item_id)
    if item is None or item.trip_id != trip_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "item not found")
    await session.delete(item)
    await session.commit()
    await publish_trip(
        str(trip_id),
        json.dumps({"type": "checklist_removed", "id": str(item_id)}),
    )

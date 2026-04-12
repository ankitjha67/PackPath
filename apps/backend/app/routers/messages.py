from __future__ import annotations

import json
import uuid

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import current_user, require_trip_member
from ..models.message import Message
from ..models.trip import TripMember
from ..models.user import User
from ..redis import publish_trip
from ..schemas.message import MessageCreate, MessageOut

router = APIRouter(prefix="/trips/{trip_id}/messages", tags=["messages"])


@router.get("", response_model=list[MessageOut])
async def list_messages(
    trip_id: uuid.UUID,
    limit: int = Query(default=50, ge=1, le=200),
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> list[MessageOut]:
    rows = (
        await session.scalars(
            select(Message)
            .where(Message.trip_id == trip_id)
            .order_by(desc(Message.sent_at))
            .limit(limit)
        )
    ).all()
    return [MessageOut.model_validate(m) for m in reversed(rows)]


@router.post("", response_model=MessageOut, status_code=status.HTTP_201_CREATED)
async def post_message(
    trip_id: uuid.UUID,
    payload: MessageCreate,
    user: User = Depends(current_user),
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> MessageOut:
    msg = Message(trip_id=trip_id, user_id=user.id, body=payload.body, kind="text")
    session.add(msg)
    await session.commit()
    await session.refresh(msg)
    out = MessageOut.model_validate(msg)
    await publish_trip(
        str(trip_id),
        json.dumps({"type": "message", **out.model_dump(mode="json")}),
    )
    return out

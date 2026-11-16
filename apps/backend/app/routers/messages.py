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
    # Resolve every sender's name + avatar in one query (no N+1) so the chat
    # shows friendly handles instead of raw UUIDs.
    identities: dict[uuid.UUID, tuple[str | None, str | None]] = {}
    user_ids = {m.user_id for m in rows}
    if user_ids:
        users = (
            await session.scalars(select(User).where(User.id.in_(user_ids)))
        ).all()
        identities = {u.id: (u.display_name, u.avatar_url) for u in users}
    return [
        MessageOut(
            id=m.id,
            trip_id=m.trip_id,
            user_id=m.user_id,
            display_name=identities.get(m.user_id, (None, None))[0],
            avatar_url=identities.get(m.user_id, (None, None))[1],
            body=m.body,
            kind=m.kind,
            sent_at=m.sent_at,
        )
        for m in reversed(rows)
    ]


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
    out = MessageOut(
        id=msg.id,
        trip_id=msg.trip_id,
        user_id=msg.user_id,
        display_name=user.display_name,
        avatar_url=user.avatar_url,
        body=msg.body,
        kind=msg.kind,
        sent_at=msg.sent_at,
    )
    await publish_trip(
        str(trip_id),
        json.dumps({"type": "message", **out.model_dump(mode="json")}),
    )
    return out

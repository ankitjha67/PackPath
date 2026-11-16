from __future__ import annotations

import json
import secrets
import uuid
from pathlib import Path

from fastapi import (
    APIRouter,
    Depends,
    File,
    Form,
    HTTPException,
    Query,
    UploadFile,
    status,
)
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import get_settings
from ..db import get_session
from ..deps import current_user, require_trip_member
from ..models.message import Message
from ..models.trip import TripMember
from ..models.user import User
from ..redis import publish_trip
from ..schemas.message import MessageCreate, MessageOut

router = APIRouter(prefix="/trips/{trip_id}/messages", tags=["messages"])

# Max upload size and the content types we accept for chat media.
_MAX_UPLOAD_BYTES = 25 * 1024 * 1024  # 25 MB


def _kind_for(content_type: str | None) -> str:
    ct = (content_type or "").lower()
    if ct.startswith("image/"):
        return "image"
    if ct.startswith("video/"):
        return "video"
    return "file"


def _out_for(msg: Message, name: str | None, avatar: str | None) -> MessageOut:
    return MessageOut(
        id=msg.id,
        trip_id=msg.trip_id,
        user_id=msg.user_id,
        display_name=name,
        avatar_url=avatar,
        body=msg.body,
        kind=msg.kind,
        attachment_kind=msg.attachment_kind,
        attachment_url=msg.attachment_url,
        sent_at=msg.sent_at,
    )


async def _broadcast(trip_id: uuid.UUID, out: MessageOut) -> None:
    await publish_trip(
        str(trip_id),
        json.dumps({"type": "message", **out.model_dump(mode="json")}),
    )


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
    # Resolve every sender's name + avatar in one query (no N+1).
    identities: dict[uuid.UUID, tuple[str | None, str | None]] = {}
    user_ids = {m.user_id for m in rows}
    if user_ids:
        users = (
            await session.scalars(select(User).where(User.id.in_(user_ids)))
        ).all()
        identities = {u.id: (u.display_name, u.avatar_url) for u in users}
    return [
        _out_for(m, *identities.get(m.user_id, (None, None)))
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
    if not payload.body.strip() and payload.attachment_url is None:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, "message needs text or an attachment"
        )
    msg = Message(
        trip_id=trip_id,
        user_id=user.id,
        body=payload.body,
        kind="text",
        attachment_kind=payload.attachment_kind,
        attachment_url=payload.attachment_url,
    )
    session.add(msg)
    await session.commit()
    await session.refresh(msg)
    out = _out_for(msg, user.display_name, user.avatar_url)
    await _broadcast(trip_id, out)
    return out


@router.post(
    "/attachment",
    response_model=MessageOut,
    status_code=status.HTTP_201_CREATED,
)
async def post_attachment(
    trip_id: uuid.UUID,
    file: UploadFile = File(...),
    body: str = Form(default=""),
    user: User = Depends(current_user),
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> MessageOut:
    """Upload a photo / video / file and post it as a chat message."""
    data = await file.read()
    if len(data) > _MAX_UPLOAD_BYTES:
        raise HTTPException(
            status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "file too large (max 25MB)"
        )
    media_dir = Path(get_settings().media_dir)
    media_dir.mkdir(parents=True, exist_ok=True)
    suffix = Path(file.filename or "").suffix[:12]
    name = f"{secrets.token_urlsafe(16)}{suffix}"
    (media_dir / name).write_bytes(data)
    url = f"/media/{name}"
    kind = _kind_for(file.content_type)

    msg = Message(
        trip_id=trip_id,
        user_id=user.id,
        body=body,
        kind="text",
        attachment_kind=kind,
        attachment_url=url,
    )
    session.add(msg)
    await session.commit()
    await session.refresh(msg)
    out = _out_for(msg, user.display_name, user.avatar_url)
    await _broadcast(trip_id, out)
    return out

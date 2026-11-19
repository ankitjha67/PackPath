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
from ..models.message_reaction import MessageReaction
from ..models.trip import TripMember
from ..models.user import User
from ..redis import publish_trip
from ..schemas.message import AnnouncementCreate, MessageCreate, MessageOut

router = APIRouter(prefix="/trips/{trip_id}/messages", tags=["messages"])

# Max upload size and the content types we accept for chat media.
_MAX_UPLOAD_BYTES = 25 * 1024 * 1024  # 25 MB

# Only keep a filename suffix if it's a known-safe media type. Anything else
# (e.g. .html, .svg, .xml, .js) is stored without an extension so it can never
# be served as active content from the API origin (stored-XSS guard).
_ALLOWED_UPLOAD_EXTS = {
    ".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic", ".heif", ".bmp",
    ".mp4", ".mov", ".m4v", ".webm", ".3gp",
    ".pdf", ".txt", ".csv",
}


def _ensure_not_muted(member: TripMember) -> None:
    """A member muted by the marshall cannot broadcast (chat / announcements /
    attachments). Enforced server-side — the client-side gate isn't enough."""
    if member.muted:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, "you are muted in this trip"
        )


def _kind_for(content_type: str | None) -> str:
    ct = (content_type or "").lower()
    if ct.startswith("image/"):
        return "image"
    if ct.startswith("video/"):
        return "video"
    return "file"


def _out_for(
    msg: Message,
    name: str | None,
    avatar: str | None,
    *,
    reactions: dict[str, int] | None = None,
    my_reactions: list[str] | None = None,
) -> MessageOut:
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
        reactions=reactions or {},
        my_reactions=my_reactions or [],
    )


async def _reactions_for(
    session: AsyncSession, message_ids: list[uuid.UUID], me: uuid.UUID
) -> tuple[dict[uuid.UUID, dict[str, int]], dict[uuid.UUID, list[str]]]:
    """Return {message_id: {emoji: count}} and {message_id: [my emojis]}."""
    counts: dict[uuid.UUID, dict[str, int]] = {}
    mine: dict[uuid.UUID, list[str]] = {}
    if not message_ids:
        return counts, mine
    rows = (
        await session.execute(
            select(
                MessageReaction.message_id,
                MessageReaction.emoji,
                MessageReaction.user_id,
            ).where(MessageReaction.message_id.in_(message_ids))
        )
    ).all()
    for mid, emoji, uid in rows:
        counts.setdefault(mid, {})
        counts[mid][emoji] = counts[mid].get(emoji, 0) + 1
        if uid == me:
            mine.setdefault(mid, []).append(emoji)
    return counts, mine


async def _broadcast(trip_id: uuid.UUID, out: MessageOut) -> None:
    await publish_trip(
        str(trip_id),
        json.dumps({"type": "message", **out.model_dump(mode="json")}),
    )


async def _require_owner(
    trip_id: uuid.UUID, user_id: uuid.UUID, session: AsyncSession
) -> None:
    """Only the trip owner (the pack marshall) may broadcast announcements."""
    member = await session.scalar(
        select(TripMember).where(
            TripMember.trip_id == trip_id, TripMember.user_id == user_id
        )
    )
    if member is None or member.role != "owner":
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            "only the pack marshall can broadcast announcements",
        )


@router.get("", response_model=list[MessageOut])
async def list_messages(
    trip_id: uuid.UUID,
    limit: int = Query(default=50, ge=1, le=200),
    user: User = Depends(current_user),
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
    counts, mine = await _reactions_for(session, [m.id for m in rows], user.id)
    return [
        _out_for(
            m,
            *identities.get(m.user_id, (None, None)),
            reactions=counts.get(m.id),
            my_reactions=mine.get(m.id),
        )
        for m in reversed(rows)
    ]


@router.post("", response_model=MessageOut, status_code=status.HTTP_201_CREATED)
async def post_message(
    trip_id: uuid.UUID,
    payload: MessageCreate,
    user: User = Depends(current_user),
    member: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> MessageOut:
    _ensure_not_muted(member)
    if not payload.body.strip() and payload.attachment_url is None:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, "message needs text or an attachment"
        )
    # A client-supplied attachment_url may only reference a file already
    # uploaded to this server (/media/...). Reject absolute/external URLs so a
    # member can't turn a chat message into a tracking pixel or phishing link.
    if payload.attachment_url is not None and not payload.attachment_url.startswith(
        "/media/"
    ):
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "attachment_url must reference an uploaded /media file",
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


@router.get("/media", response_model=list[MessageOut])
async def list_media(
    trip_id: uuid.UUID,
    limit: int = Query(default=120, ge=1, le=500),
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> list[MessageOut]:
    """Every photo / video shared in the trip chat — the trip gallery."""
    rows = (
        await session.scalars(
            select(Message)
            .where(
                Message.trip_id == trip_id,
                Message.attachment_kind.in_(("image", "video")),
            )
            .order_by(desc(Message.sent_at))
            .limit(limit)
        )
    ).all()
    identities: dict[uuid.UUID, tuple[str | None, str | None]] = {}
    user_ids = {m.user_id for m in rows}
    if user_ids:
        users = (
            await session.scalars(select(User).where(User.id.in_(user_ids)))
        ).all()
        identities = {u.id: (u.display_name, u.avatar_url) for u in users}
    return [_out_for(m, *identities.get(m.user_id, (None, None))) for m in rows]


@router.get("/announcement", response_model=MessageOut | None)
async def latest_announcement(
    trip_id: uuid.UUID,
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> MessageOut | None:
    """The most recent pinned announcement for this trip, or null."""
    msg = await session.scalar(
        select(Message)
        .where(Message.trip_id == trip_id, Message.kind == "announcement")
        .order_by(desc(Message.sent_at))
        .limit(1)
    )
    if msg is None:
        return None
    sender = await session.get(User, msg.user_id)
    return _out_for(
        msg,
        sender.display_name if sender else None,
        sender.avatar_url if sender else None,
    )


@router.post(
    "/announcement",
    response_model=MessageOut,
    status_code=status.HTTP_201_CREATED,
)
async def post_announcement(
    trip_id: uuid.UUID,
    payload: AnnouncementCreate,
    user: User = Depends(current_user),
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> MessageOut:
    """Marshall-only broadcast: a pinned announcement to the whole pack."""
    await _require_owner(trip_id, user.id, session)
    body = payload.body.strip()
    has_rally = payload.lat is not None and payload.lng is not None
    if not body and not has_rally:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, "announcement needs text or a rally point"
        )
    msg = Message(
        trip_id=trip_id,
        user_id=user.id,
        body=body or ("Regroup here" if has_rally else ""),
        kind="announcement",
        attachment_kind="location" if has_rally else None,
        attachment_url=f"{payload.lat},{payload.lng}" if has_rally else None,
    )
    session.add(msg)
    await session.commit()
    await session.refresh(msg)
    out = _out_for(msg, user.display_name, user.avatar_url)
    await _broadcast(trip_id, out)
    return out


@router.post("/{message_id}/reactions")
async def toggle_reaction(
    trip_id: uuid.UUID,
    message_id: uuid.UUID,
    emoji: str = Form(default=""),
    user: User = Depends(current_user),
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """Toggle one emoji reaction on a message. Fans out a 'reaction' frame so
    every open chat updates live, and returns the message's fresh counts."""
    emoji = emoji.strip()
    if not emoji or len(emoji) > 16:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "invalid emoji")
    msg = await session.get(Message, message_id)
    if msg is None or msg.trip_id != trip_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "message not found")
    existing = await session.scalar(
        select(MessageReaction).where(
            MessageReaction.message_id == message_id,
            MessageReaction.user_id == user.id,
            MessageReaction.emoji == emoji,
        )
    )
    if existing is None:
        session.add(
            MessageReaction(message_id=message_id, user_id=user.id, emoji=emoji)
        )
        added = True
    else:
        await session.delete(existing)
        added = False
    await session.commit()
    counts, _mine = await _reactions_for(session, [message_id], user.id)
    emoji_counts = counts.get(message_id, {})
    await publish_trip(
        str(trip_id),
        json.dumps(
            {
                "type": "reaction",
                "message_id": str(message_id),
                "emoji": emoji,
                "user_id": str(user.id),
                "added": added,
                "counts": emoji_counts,
            }
        ),
    )
    return {"added": added, "counts": emoji_counts}


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
    member: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> MessageOut:
    """Upload a photo / video / file and post it as a chat message."""
    _ensure_not_muted(member)
    data = await file.read()
    if len(data) > _MAX_UPLOAD_BYTES:
        raise HTTPException(
            status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "file too large (max 25MB)"
        )
    media_dir = Path(get_settings().media_dir)
    media_dir.mkdir(parents=True, exist_ok=True)
    raw_suffix = Path(file.filename or "").suffix.lower()
    suffix = raw_suffix if raw_suffix in _ALLOWED_UPLOAD_EXTS else ""
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

"""Background task: fire due scheduled announcements.

Polls every few seconds for scheduled announcements whose time has come,
posts each as a pinned announcement message (the same shape the chat/announce
endpoint produces) and broadcasts it over the trip WebSocket.
"""
from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime, timezone

from sqlalchemy import select

from ..db import SessionLocal
from ..models.message import Message
from ..models.scheduled import ScheduledAnnouncement
from ..models.user import User
from ..redis import publish_trip

logger = logging.getLogger(__name__)


async def _tick() -> None:
    async with SessionLocal() as session:
        now = datetime.now(tz=timezone.utc)
        due = (
            await session.scalars(
                select(ScheduledAnnouncement).where(
                    ScheduledAnnouncement.sent.is_(False),
                    ScheduledAnnouncement.send_at <= now,
                )
            )
        ).all()
        for sched in due:
            sched.sent = True
            if sched.created_by is None:
                continue
            msg = Message(
                trip_id=sched.trip_id,
                user_id=sched.created_by,
                body=sched.body,
                kind="announcement",
            )
            session.add(msg)
            await session.flush()
            await session.refresh(msg)
            user = await session.get(User, sched.created_by)
            payload = {
                "type": "message",
                "id": str(msg.id),
                "trip_id": str(msg.trip_id),
                "user_id": str(msg.user_id),
                "display_name": user.display_name if user else None,
                "avatar_url": user.avatar_url if user else None,
                "body": msg.body,
                "kind": msg.kind,
                "attachment_kind": None,
                "attachment_url": None,
                "sent_at": msg.sent_at.isoformat(),
                "reactions": {},
                "my_reactions": [],
            }
            await publish_trip(str(msg.trip_id), json.dumps(payload))
        await session.commit()


async def run_scheduled_sender(interval_seconds: int = 15) -> None:
    """Run forever, firing due announcements on each interval."""
    while True:
        try:
            await _tick()
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001 - keep the loop alive on any error
            logger.exception("scheduled announcement tick failed")
        await asyncio.sleep(interval_seconds)

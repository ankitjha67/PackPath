"""Firebase Cloud Messaging push.

Lazy-initialised: if `FCM_SERVICE_ACCOUNT_JSON` is unset (or
firebase_admin isn't installed), every send is a silent no-op so local
dev keeps working without a Firebase project.
"""

from __future__ import annotations

import asyncio
import json
import os
import uuid
from datetime import datetime, timezone
from typing import Iterable

from loguru import logger
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import get_settings
from ..models.device import Device
from ..models.notification_pref import NotificationPreferences

_initialised: bool | None = None


def _in_quiet_hours(prefs: NotificationPreferences, hour: int) -> bool:
    start, end = prefs.quiet_start, prefs.quiet_end
    if start is None or end is None or start == end:
        return False
    if start < end:
        return start <= hour < end
    # Wrap-around window (e.g. 22 -> 7).
    return hour >= start or hour < end


async def eligible_user_ids(
    session: AsyncSession,
    user_ids: Iterable[str | uuid.UUID],
    category: str,
    *,
    now: datetime | None = None,
) -> list[str]:
    """Filter a set of users down to those who should receive a push in this
    category right now, honouring the master switch, the per-category toggle,
    and quiet hours. Safety always passes (life-safety overrides)."""
    ids = [str(u) for u in user_ids]
    if not ids:
        return []
    if category == "safety":
        return ids
    now = now or datetime.now(tz=timezone.utc)
    hour = now.astimezone(timezone.utc).hour
    rows = {
        str(p.user_id): p
        for p in (
            await session.scalars(
                select(NotificationPreferences).where(
                    NotificationPreferences.user_id.in_(ids)
                )
            )
        ).all()
    }
    out: list[str] = []
    for uid in ids:
        prefs = rows.get(uid)
        if prefs is None:
            out.append(uid)  # no row yet = all-on defaults
            continue
        if not prefs.enabled:
            continue
        if not bool(getattr(prefs, category, True)):
            continue
        if _in_quiet_hours(prefs, hour):
            continue
        out.append(uid)
    return out


def _ensure_initialised() -> bool:
    """Returns True iff firebase_admin is importable AND a service account
    is configured. Caches the result so subsequent calls are cheap."""
    global _initialised
    if _initialised is not None:
        return _initialised

    settings = get_settings()
    payload = settings.fcm_service_account_json
    if not payload:
        _initialised = False
        return False

    try:
        import firebase_admin  # type: ignore
        from firebase_admin import credentials  # type: ignore
    except Exception as exc:  # ImportError or platform-specific issues
        logger.warning("firebase_admin unavailable: {}", exc)
        _initialised = False
        return False

    try:
        if payload.startswith("{"):
            cred_dict = json.loads(payload)
        elif os.path.exists(payload):
            with open(payload, "r", encoding="utf-8") as fh:
                cred_dict = json.load(fh)
        else:
            cred_dict = json.loads(payload)
        cred = credentials.Certificate(cred_dict)
        if not firebase_admin._apps:
            firebase_admin.initialize_app(cred)
    except Exception as exc:
        logger.warning("firebase_admin init failed: {}", exc)
        _initialised = False
        return False

    _initialised = True
    return True


async def push_to_users(
    *,
    session: AsyncSession,
    user_ids: Iterable[str | uuid.UUID],
    category: str,
    title: str,
    body: str,
    data: dict[str, str] | None = None,
) -> int:
    """Send a push to the given users, gated by each user's notification
    preferences + quiet hours (safety bypasses both). Returns the number of
    device messages FCM accepted — 0 in dev where FCM isn't configured, so this
    is always safe to call inline."""
    targets = await eligible_user_ids(session, user_ids, category)
    if not targets:
        return 0
    if not await asyncio.to_thread(_ensure_initialised):
        # Dev / no-FCM: log the intent so the pipeline is observable.
        logger.info(
            "push suppressed (FCM not configured): category={} users={} title={}",
            category,
            len(targets),
            title,
        )
        return 0

    rows = (
        await session.scalars(
            select(Device).where(Device.user_id.in_(targets))
        )
    ).all()
    tokens = [d.fcm_token for d in rows]
    if not tokens:
        return 0

    try:
        from firebase_admin import messaging  # type: ignore
    except Exception as exc:
        logger.warning("firebase_admin.messaging unavailable: {}", exc)
        return 0

    payload = {"category": category, **{k: str(v) for k, v in (data or {}).items()}}
    msg = messaging.MulticastMessage(
        tokens=tokens,
        notification=messaging.Notification(title=title, body=body),
        data=payload,
    )
    try:
        # send_each_for_multicast does blocking HTTP to FCM — never call it
        # directly from the async WS ingest loop or it stalls every socket.
        result = await asyncio.to_thread(messaging.send_each_for_multicast, msg)
        return result.success_count
    except Exception as exc:
        logger.warning("fcm send failed: {}", exc)
        return 0


async def push_chat_to_users(
    *,
    session: AsyncSession,
    user_ids: Iterable[str],
    title: str,
    body: str,
    data: dict[str, str] | None = None,
) -> int:
    """Back-compat shim for the chat push path — now routed through the
    preference-gated dispatcher under the 'chat' category."""
    return await push_to_users(
        session=session,
        user_ids=user_ids,
        category="chat",
        title=title,
        body=body,
        data=data,
    )

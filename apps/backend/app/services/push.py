"""Firebase Cloud Messaging push.

Lazy-initialised: if `FCM_SERVICE_ACCOUNT_JSON` is unset (or
firebase_admin isn't installed), every send is a silent no-op so local
dev keeps working without a Firebase project.
"""

from __future__ import annotations

import json
import os
from typing import Iterable

from loguru import logger
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import get_settings
from ..models.device import Device

_initialised: bool | None = None


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


async def push_chat_to_users(
    *,
    session: AsyncSession,
    user_ids: Iterable[str],
    title: str,
    body: str,
    data: dict[str, str] | None = None,
) -> int:
    user_ids = list(user_ids)
    if not user_ids:
        return 0
    if not _ensure_initialised():
        return 0

    rows = (
        await session.scalars(
            select(Device).where(Device.user_id.in_(user_ids))
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

    msg = messaging.MulticastMessage(
        tokens=tokens,
        notification=messaging.Notification(title=title, body=body),
        data={k: str(v) for k, v in (data or {}).items()},
    )
    try:
        result = messaging.send_each_for_multicast(msg)
        return result.success_count
    except Exception as exc:
        logger.warning("fcm send failed: {}", exc)
        return 0

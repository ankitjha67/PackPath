"""FCM device registration.

Phones POST their token here on first launch (or whenever it rotates).
The actual `firebase_admin.messaging.send_each_for_multicast` call lives
in services/push.py once we wire FCM in Weekend 5.
"""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Response, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import current_user
from ..models.device import Device
from ..models.user import User

router = APIRouter(prefix="/devices", tags=["devices"])


class DeviceRegister(BaseModel):
    fcm_token: str = Field(min_length=10, max_length=500)
    platform: str = Field(pattern="^(ios|android|web)$")


@router.post(
    "",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
    response_model=None,
)
async def register_device(
    payload: DeviceRegister,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> None:
    # Upsert on the unique fcm_token so two concurrent registrations of the
    # same token (app-start retry storms) don't race into a duplicate-key 500.
    stmt = pg_insert(Device).values(
        user_id=user.id,
        fcm_token=payload.fcm_token,
        platform=payload.platform,
    )
    stmt = stmt.on_conflict_do_update(
        index_elements=[Device.fcm_token],
        set_={
            "user_id": user.id,
            "platform": payload.platform,
            "last_seen_at": datetime.now(tz=timezone.utc),
        },
    )
    await session.execute(stmt)
    await session.commit()


@router.delete(
    "/{fcm_token}",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
    response_model=None,
)
async def unregister_device(
    fcm_token: str,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> None:
    existing = await session.scalar(
        select(Device).where(
            Device.fcm_token == fcm_token, Device.user_id == user.id
        )
    )
    if existing is not None:
        await session.delete(existing)
        await session.commit()

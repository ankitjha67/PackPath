from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import Boolean, ForeignKey, SmallInteger, text
from sqlalchemy.dialects.postgresql import TIMESTAMP, UUID
from sqlalchemy.orm import Mapped, mapped_column

from ..db import Base

# Notification categories a user can toggle. 'safety' is intentionally absent
# from the opt-out set — SOS/crash always push (life-safety overrides).
NOTIFICATION_CATEGORIES = (
    "announcements",
    "nudges",
    "detours",
    "hazards",
    "chat",
    "checklist",
)


class NotificationPreferences(Base):
    """Per-user push notification preferences (Phase 9). One row per user,
    created lazily with everything on. Quiet hours suppress non-safety pushes;
    the master `enabled` switch does the same. Safety (SOS/crash) always pushes.
    """

    __tablename__ = "notification_preferences"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        primary_key=True,
    )
    enabled: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default=text("true")
    )
    announcements: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default=text("true")
    )
    nudges: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default=text("true")
    )
    detours: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default=text("true")
    )
    hazards: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default=text("true")
    )
    chat: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default=text("true")
    )
    checklist: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default=text("true")
    )
    # Quiet hours (UTC hour-of-day 0-23). When both set, non-safety pushes are
    # suppressed inside the window (wrap-around supported, e.g. 22 -> 7).
    quiet_start: Mapped[int | None] = mapped_column(SmallInteger)
    quiet_end: Mapped[int | None] = mapped_column(SmallInteger)
    updated_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True), server_default=text("now()"), nullable=False
    )

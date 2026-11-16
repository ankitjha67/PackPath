from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import CheckConstraint, ForeignKey, String, Text, text
from sqlalchemy.dialects.postgresql import TIMESTAMP, UUID
from sqlalchemy.orm import Mapped, mapped_column

from ..db import Base


class Message(Base):
    __tablename__ = "messages"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()")
    )
    trip_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("trips.id", ondelete="CASCADE"), nullable=False
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    body: Mapped[str] = mapped_column(Text, nullable=False)
    kind: Mapped[str] = mapped_column(String(20), nullable=False, default="text")
    # Optional attachment: image | video | file | location.
    # For media, attachment_url is a served /media path; for location it holds
    # "lat,lng". body carries an optional caption / place label.
    attachment_kind: Mapped[str | None] = mapped_column(String(12))
    attachment_url: Mapped[str | None] = mapped_column(String(500))
    sent_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True), server_default=text("now()"), nullable=False
    )

    __table_args__ = (
        CheckConstraint(
            "kind in ('text','system','arrival','leave','join')",
            name="messages_kind_check",
        ),
    )

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import ForeignKey, String, UniqueConstraint, text
from sqlalchemy.dialects.postgresql import TIMESTAMP, UUID
from sqlalchemy.orm import Mapped, mapped_column

from ..db import Base


class ContactRequest(Base):
    """A request from one trip member to exchange phone numbers with another.

    Scoped to a single trip (per the product decision): an accepted request
    only reveals the two phone numbers to each other *within that trip*. A
    pair is "connected" for the trip when a row between them (either
    direction) has status ``accepted``.
    """

    __tablename__ = "contact_requests"
    __table_args__ = (
        # One active request per (trip, requester, target) direction.
        UniqueConstraint(
            "trip_id",
            "requester_id",
            "target_id",
            name="uq_contact_request_direction",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default=text("gen_random_uuid()"),
    )
    trip_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("trips.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    requester_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    target_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    # pending | accepted | declined
    status: Mapped[str] = mapped_column(
        String(10), nullable=False, default="pending"
    )
    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True), server_default=text("now()"), nullable=False
    )
    responded_at: Mapped[datetime | None] = mapped_column(
        TIMESTAMP(timezone=True)
    )

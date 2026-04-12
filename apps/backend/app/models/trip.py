from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import Boolean, CheckConstraint, ForeignKey, String, text
from sqlalchemy.dialects.postgresql import JSONB, TIMESTAMP, UUID
from sqlalchemy.orm import Mapped, mapped_column

from ..db import Base


class Trip(Base):
    __tablename__ = "trips"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()")
    )
    owner_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="planned")
    start_at: Mapped[datetime | None] = mapped_column(TIMESTAMP(timezone=True))
    end_at: Mapped[datetime | None] = mapped_column(TIMESTAMP(timezone=True))
    join_code: Mapped[str] = mapped_column(String(6), unique=True, nullable=False)
    template: Mapped[str | None] = mapped_column(String(40))
    cover_color: Mapped[str] = mapped_column(
        String(9), nullable=False, default="#3B82F6"
    )
    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True), server_default=text("now()"), nullable=False
    )

    __table_args__ = (
        CheckConstraint(
            "status in ('planned','active','ended','cancelled')",
            name="trips_status_check",
        ),
    )


class TripMember(Base):
    __tablename__ = "trip_members"

    trip_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("trips.id", ondelete="CASCADE"), primary_key=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    role: Mapped[str] = mapped_column(String(20), nullable=False, default="member")
    color: Mapped[str] = mapped_column(String(9), nullable=False, default="#3B82F6")
    joined_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True), server_default=text("now()"), nullable=False
    )
    left_at: Mapped[datetime | None] = mapped_column(TIMESTAMP(timezone=True))
    ghost_mode: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    is_ready: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    visibility_scope: Mapped[dict[str, Any]] = mapped_column(
        JSONB, nullable=False, default=lambda: {"type": "all"}
    )
    share_until: Mapped[datetime | None] = mapped_column(TIMESTAMP(timezone=True))
    vehicle_label: Mapped[str | None] = mapped_column(String(40))
    subgroup_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("subgroups.id", ondelete="SET NULL")
    )

    __table_args__ = (
        CheckConstraint(
            "role in ('owner','member','driver','navigator','dj','photographer','treasurer')",
            name="trip_members_role_check",
        ),
    )

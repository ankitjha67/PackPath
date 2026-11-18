from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    ForeignKey,
    Integer,
    String,
    text,
)
from sqlalchemy.dialects.postgresql import TIMESTAMP, UUID
from sqlalchemy.orm import Mapped, mapped_column

from ..db import Base

# Logistics (Phase 6): a shared, live trip checklist. One row per thing the
# pack needs to pack, buy, or do — claimable ("I've got it") and checkable.
CHECKLIST_CATEGORIES = (
    "packing",
    "supplies",
    "food",
    "gear",
    "todo",
    "other",
)


class ChecklistItem(Base):
    """A single shared checklist line for a trip. `assigned_to` is who has
    taken responsibility (claimed it); `done` + `done_by` track completion."""

    __tablename__ = "checklist_items"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()")
    )
    trip_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("trips.id", ondelete="CASCADE"),
        nullable=False,
    )
    title: Mapped[str] = mapped_column(String(160), nullable=False)
    category: Mapped[str] = mapped_column(
        String(16), nullable=False, default="packing"
    )
    # Optional quantity / count (e.g. "4" tents). 1 when unset.
    qty: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    created_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL")
    )
    assigned_to: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL")
    )
    done: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    done_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL")
    )
    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True), server_default=text("now()"), nullable=False
    )

    __table_args__ = (
        CheckConstraint(
            "category in ('packing','supplies','food','gear','todo','other')",
            name="checklist_items_category_check",
        ),
        CheckConstraint("qty >= 1", name="checklist_items_qty_check"),
    )

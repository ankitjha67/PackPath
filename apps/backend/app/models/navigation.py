from __future__ import annotations

import uuid
from datetime import datetime

from geoalchemy2 import Geography
from sqlalchemy import (
    CheckConstraint,
    ForeignKey,
    String,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import TIMESTAMP, UUID
from sqlalchemy.orm import Mapped, mapped_column

from ..db import Base

# Live, member-reported road hazards — distinct from the global NASA EONET
# environmental feed (/hazards). These are the pothole / accident / police /
# roadblock reports a pack drops for each other in real time on one trip.
ROAD_HAZARD_KINDS = (
    "pothole",
    "accident",
    "police",
    "traffic",
    "roadblock",
    "animal",
    "debris",
    "flood",
    "construction",
    "fuel_closed",
    "landslide",
    "other",
)

ROAD_HAZARD_SEVERITIES = ("info", "warn", "danger")


class RoadHazard(Base):
    """A hazard a member drops on the shared route so the pack behind them is
    warned. Scoped to one trip, short-lived (expires), and clearable once the
    obstruction is gone."""

    __tablename__ = "road_hazards"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()")
    )
    trip_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("trips.id", ondelete="CASCADE"),
        nullable=False,
    )
    user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL")
    )
    kind: Mapped[str] = mapped_column(String(20), nullable=False, default="other")
    severity: Mapped[str] = mapped_column(String(10), nullable=False, default="warn")
    geom = mapped_column(Geography(geometry_type="POINT", srid=4326), nullable=False)
    note: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True), server_default=text("now()"), nullable=False
    )
    # Auto-stale after this time so the map never shows yesterday's pothole.
    expires_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True), nullable=False
    )
    cleared_at: Mapped[datetime | None] = mapped_column(TIMESTAMP(timezone=True))
    cleared_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL")
    )

    __table_args__ = (
        CheckConstraint(
            "kind in ('pothole','accident','police','traffic','roadblock',"
            "'animal','debris','flood','construction','fuel_closed',"
            "'landslide','other')",
            name="road_hazards_kind_check",
        ),
        CheckConstraint(
            "severity in ('info','warn','danger')",
            name="road_hazards_severity_check",
        ),
    )


class DetourProposal(Base):
    """A proposal to reroute the pack to a new target (a place, waypoint, or
    dropped pin). Members vote; whoever proposed (or the trip owner) closes it.
    Reuses the ready-check voting pattern, applied to a map decision."""

    __tablename__ = "detour_proposals"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()")
    )
    trip_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("trips.id", ondelete="CASCADE"),
        nullable=False,
    )
    proposed_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL")
    )
    label: Mapped[str] = mapped_column(String(160), nullable=False)
    reason: Mapped[str | None] = mapped_column(Text)
    geom = mapped_column(Geography(geometry_type="POINT", srid=4326), nullable=False)
    # Optional link back to an establishment so a rest-stop detour carries its
    # rating/context.
    establishment_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("establishments.id", ondelete="SET NULL")
    )
    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True), server_default=text("now()"), nullable=False
    )
    resolved_at: Mapped[datetime | None] = mapped_column(TIMESTAMP(timezone=True))
    # One of: null (open), 'accepted', 'rejected', 'cancelled'.
    outcome: Mapped[str | None] = mapped_column(String(12))

    __table_args__ = (
        CheckConstraint(
            "outcome is null or outcome in ('accepted','rejected','cancelled')",
            name="detour_proposals_outcome_check",
        ),
    )


class DetourVote(Base):
    """One member's vote on a detour proposal. Unique per (proposal, user) so a
    changed vote is an upsert."""

    __tablename__ = "detour_votes"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()")
    )
    proposal_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("detour_proposals.id", ondelete="CASCADE"),
        nullable=False,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    # 'yes' or 'no'.
    choice: Mapped[str] = mapped_column(String(3), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True), server_default=text("now()"), nullable=False
    )

    __table_args__ = (
        CheckConstraint("choice in ('yes','no')", name="detour_votes_choice_check"),
        UniqueConstraint("proposal_id", "user_id", name="uq_detour_vote_user"),
    )

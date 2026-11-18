from __future__ import annotations

import uuid
from datetime import datetime

from geoalchemy2 import Geography
from sqlalchemy import (
    CheckConstraint,
    ForeignKey,
    SmallInteger,
    String,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import TIMESTAMP, UUID
from sqlalchemy.orm import Mapped, mapped_column

from ..db import Base

# Categories of establishment a pack might mark along a route. Kept broad so
# the same directory serves bike rides, treks, road trips and convoys.
ESTABLISHMENT_CATEGORIES = (
    "fuel",
    "food",
    "repair",
    "lodging",
    "viewpoint",
    "medical",
    "atm",
    "parking",
    "water",
    "shop",
    "other",
)


class Establishment(Base):
    """A real-world place (fuel pump, dhaba, mechanic, viewpoint, ...) that
    members mark on the map. Global — not tied to one trip — so a place rated
    on one trip is discoverable and reusable on every future trip."""

    __tablename__ = "establishments"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()")
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    category: Mapped[str] = mapped_column(String(20), nullable=False, default="other")
    geom = mapped_column(Geography(geometry_type="POINT", srid=4326), nullable=False)
    address: Mapped[str | None] = mapped_column(String(300))
    phone: Mapped[str | None] = mapped_column(String(30))
    notes: Mapped[str | None] = mapped_column(Text)
    created_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL")
    )
    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True), server_default=text("now()"), nullable=False
    )

    __table_args__ = (
        CheckConstraint(
            "category in ('fuel','food','repair','lodging','viewpoint',"
            "'medical','atm','parking','water','shop','other')",
            name="establishments_category_check",
        ),
    )


class EstablishmentRating(Base):
    """One member's rating of an establishment. Unique per (place, user) so a
    member's rating is an upsert, and aggregates stay honest."""

    __tablename__ = "establishment_ratings"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()")
    )
    establishment_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("establishments.id", ondelete="CASCADE"),
        nullable=False,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    stars: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    comment: Mapped[str | None] = mapped_column(Text)
    # Comma-separated service tags, e.g. "quick service,fair price,clean".
    tags: Mapped[str | None] = mapped_column(String(200))
    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True), server_default=text("now()"), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True),
        server_default=text("now()"),
        nullable=False,
    )

    __table_args__ = (
        CheckConstraint("stars between 1 and 5", name="establishment_ratings_stars_check"),
        UniqueConstraint(
            "establishment_id", "user_id", name="uq_establishment_rating_user"
        ),
    )

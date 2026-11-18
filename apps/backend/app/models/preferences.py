from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import Boolean, CheckConstraint, Float, ForeignKey, String, text
from sqlalchemy.dialects.postgresql import TIMESTAMP, UUID
from sqlalchemy.orm import Mapped, mapped_column

from ..db import Base

VEHICLE_TYPES = (
    "motorcycle",
    "scooter",
    "hatchback",
    "sedan",
    "suv",
    "van",
    "truck",
    "bicycle",
    "other",
)


class UserPreferences(Base):
    """Per-user personalization (Phase 8), synced server-side so it follows the
    user across devices. One row per user, created lazily on first read."""

    __tablename__ = "user_preferences"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        primary_key=True,
    )
    # 'metric' (km) or 'imperial' (mi).
    units: Mapped[str] = mapped_column(String(10), nullable=False, default="metric")
    # 'c' or 'f'.
    temp_unit: Mapped[str] = mapped_column(String(1), nullable=False, default="c")
    # Preferred map tile/routing provider id (mirrors MapProvider ids).
    map_style: Mapped[str] = mapped_column(String(20), nullable=False, default="mapbox")
    vehicle_type: Mapped[str] = mapped_column(
        String(20), nullable=False, default="hatchback"
    )
    # Fuel efficiency in km per litre, used to sharpen cost estimates.
    mileage_kmpl: Mapped[float | None] = mapped_column(Float)
    # Default location-sharing on joining a trip.
    share_location_default: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default=text("true")
    )
    updated_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True),
        server_default=text("now()"),
        nullable=False,
    )

    __table_args__ = (
        CheckConstraint("units in ('metric','imperial')", name="user_prefs_units_check"),
        CheckConstraint("temp_unit in ('c','f')", name="user_prefs_temp_check"),
    )

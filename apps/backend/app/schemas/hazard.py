"""Pydantic schemas for NASA EONET hazards.

EONET (Earth Observatory Natural Event Tracker) emits geodetic events
that we normalize into this internal `Hazard` shape before serving them
to mobile clients. The mobile app speaks only this schema — upstream
EONET structure is hidden behind `eonet_service.fetch_hazards`.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


class HazardGeometry(BaseModel):
    """One geometry datum attached to a hazard event.

    EONET emits either Points (e.g. earthquake epicentres, active
    wildfires) or Polygons (e.g. smoke plumes, iceberg outlines).
    Coordinates follow GeoJSON convention (lng, lat) for Point and
    [[[lng, lat], ...]] for Polygon rings.
    """

    type: Literal["Point", "Polygon"]
    # Point: [lng, lat]  |  Polygon: [[[lng, lat], ...], ...]
    coordinates: list
    date: datetime | None = None


class Hazard(BaseModel):
    """Normalized hazard event served at GET /hazards."""

    id: str = Field(min_length=1)
    title: str
    category: str = Field(
        description="One of: wildfires, severeStorms, volcanoes, seaLakeIce, "
        "earthquakes, floods, landslides, drought, dustHaze, manmade, snow, "
        "tempExtremes, waterColor"
    )
    severity: str = Field(
        default="info",
        description="Coarse severity bucket inferred from upstream magnitude / "
        "category. One of: info, warning, severe.",
    )
    updated_at: datetime
    geometries: list[HazardGeometry]
    source_url: str | None = None


class HazardsResponse(BaseModel):
    hazards: list[Hazard]
    cached: bool = Field(
        description="True if the response was served from Redis without "
        "touching EONET upstream."
    )
    fetched_at: datetime

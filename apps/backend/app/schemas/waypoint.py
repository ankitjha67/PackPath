from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


_CATEGORIES = {
    "fuel",
    "food",
    "rest",
    "viewpoint",
    "overnight",
    "repair",
    "checkpoint",
    "other",
}


class WaypointCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    position: int = Field(ge=0)
    arrival_radius_m: int = Field(default=150, ge=10, le=5000)
    category: str | None = Field(default=None, max_length=20)
    notes: str | None = Field(default=None, max_length=500)


class WaypointUpdate(BaseModel):
    """Marshall/member edit of a stop's metadata (not its coordinates)."""

    name: str | None = Field(default=None, min_length=1, max_length=120)
    category: str | None = Field(default=None, max_length=20)
    notes: str | None = Field(default=None, max_length=500)
    assignee_id: uuid.UUID | None = None
    arrival_radius_m: int | None = Field(default=None, ge=10, le=5000)


class WaypointReorder(BaseModel):
    """Full ordered list of waypoint ids; positions are rewritten to match."""

    order: list[uuid.UUID] = Field(min_length=1)


class WaypointOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    trip_id: uuid.UUID
    name: str
    position: int
    lat: float
    lng: float
    arrival_radius_m: int
    category: str | None = None
    notes: str | None = None
    assignee_id: uuid.UUID | None = None
    created_at: datetime

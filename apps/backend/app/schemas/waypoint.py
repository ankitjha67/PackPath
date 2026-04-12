from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class WaypointCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    position: int = Field(ge=0)
    arrival_radius_m: int = Field(default=150, ge=10, le=5000)


class WaypointOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    trip_id: uuid.UUID
    name: str
    position: int
    lat: float
    lng: float
    arrival_radius_m: int
    created_at: datetime

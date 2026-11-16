from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class EstablishmentCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    category: str = Field(default="other", max_length=20)
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    address: str | None = Field(default=None, max_length=300)
    phone: str | None = Field(default=None, max_length=30)
    notes: str | None = Field(default=None, max_length=2000)


class EstablishmentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    category: str
    lat: float
    lng: float
    address: str | None = None
    phone: str | None = None
    notes: str | None = None
    avg_stars: float = 0.0
    rating_count: int = 0
    distance_m: float | None = None
    # The current user's own star rating, if they've rated it.
    my_stars: int | None = None
    created_at: datetime | None = None


class RatingCreate(BaseModel):
    stars: int = Field(ge=1, le=5)
    comment: str | None = Field(default=None, max_length=2000)
    tags: str | None = Field(default=None, max_length=200)


class RatingOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    reviewer_name: str | None = None
    reviewer_avatar: str | None = None
    stars: int
    comment: str | None = None
    tags: str | None = None
    created_at: datetime

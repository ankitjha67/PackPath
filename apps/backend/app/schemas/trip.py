from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class TripCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    start_at: datetime | None = None
    end_at: datetime | None = None


class TripJoinRequest(BaseModel):
    join_code: str = Field(min_length=6, max_length=6)


class TripMemberOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    user_id: uuid.UUID
    role: str
    color: str
    ghost_mode: bool
    joined_at: datetime


class TripOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    owner_id: uuid.UUID
    name: str
    status: str
    start_at: datetime | None
    end_at: datetime | None
    join_code: str
    created_at: datetime
    members: list[TripMemberOut] = Field(default_factory=list)

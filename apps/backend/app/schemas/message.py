from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class MessageCreate(BaseModel):
    # Empty body is allowed when an attachment is present (e.g. a bare photo
    # or a location pin). The endpoint rejects a message with neither.
    body: str = Field(default="", max_length=2000)
    attachment_kind: str | None = Field(default=None, max_length=12)
    attachment_url: str | None = Field(default=None, max_length=500)


class AnnouncementCreate(BaseModel):
    body: str = Field(min_length=1, max_length=2000)


class MessageOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    trip_id: uuid.UUID
    user_id: uuid.UUID
    display_name: str | None = None
    avatar_url: str | None = None
    body: str
    kind: str
    attachment_kind: str | None = None
    attachment_url: str | None = None
    sent_at: datetime

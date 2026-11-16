from __future__ import annotations

import uuid

from pydantic import BaseModel, ConfigDict, Field


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    phone: str
    display_name: str | None = None
    avatar_url: str | None = None
    bio: str | None = None
    country: str | None = None


class UserUpdate(BaseModel):
    display_name: str | None = Field(default=None, max_length=80)
    avatar_url: str | None = Field(default=None, max_length=500)
    bio: str | None = Field(default=None, max_length=300)
    country: str | None = Field(default=None, max_length=60)


class PublicProfile(BaseModel):
    """What any trip-mate may see about another user — never the phone."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    display_name: str | None = None
    avatar_url: str | None = None
    bio: str | None = None
    country: str | None = None

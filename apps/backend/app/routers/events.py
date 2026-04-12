"""Client telemetry ingestion.

Mobile clients POST batches of events to /events. The events table is
a TimescaleDB hypertable so we can roll up funnels with ordinary SQL.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, Response, status
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import current_user
from ..models.user import User

router = APIRouter(prefix="/events", tags=["events"])


class EventIn(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    properties: dict = Field(default_factory=dict)
    created_at: datetime | None = None
    session_id: str | None = None
    trip_id: uuid.UUID | None = None


class EventBatch(BaseModel):
    events: list[EventIn] = Field(min_length=1, max_length=200)


_INSERT = text(
    """
    INSERT INTO events (user_id, name, properties, created_at, session_id, trip_id)
    VALUES (:user_id, :name, CAST(:properties AS jsonb), COALESCE(:created_at, now()), :session_id, :trip_id)
    """
)


@router.post(
    "",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
    response_model=None,
)
async def ingest_events(
    payload: EventBatch,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> None:
    import json

    for ev in payload.events:
        await session.execute(
            _INSERT,
            {
                "user_id": user.id,
                "name": ev.name,
                "properties": json.dumps(ev.properties),
                "created_at": ev.created_at,
                "session_id": ev.session_id,
                "trip_id": ev.trip_id,
            },
        )
    await session.commit()

"""Safety alerts router.

Read-only history of every safety event for a trip. Writes happen
through the WebSocket ingest path (sos / crash) or server-side
detection (speed / stranded / fatigue), so this router only exposes
list + acknowledge.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import require_trip_member
from ..models.safety import SafetyAlert
from ..models.trip import TripMember

router = APIRouter(prefix="/trips/{trip_id}/safety", tags=["safety"])


class SafetyAlertOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    trip_id: uuid.UUID
    user_id: uuid.UUID
    kind: str
    severity: str
    details: dict
    created_at: datetime
    acknowledged_at: datetime | None


@router.get("", response_model=list[SafetyAlertOut])
async def list_alerts(
    trip_id: uuid.UUID,
    limit: int = 50,
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> list[SafetyAlertOut]:
    rows = (
        await session.scalars(
            select(SafetyAlert)
            .where(SafetyAlert.trip_id == trip_id)
            .order_by(desc(SafetyAlert.created_at))
            .limit(limit)
        )
    ).all()
    return [SafetyAlertOut.model_validate(r) for r in rows]


@router.post("/{alert_id}/ack", response_model=SafetyAlertOut)
async def ack_alert(
    trip_id: uuid.UUID,
    alert_id: uuid.UUID,
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> SafetyAlertOut:
    alert = await session.get(SafetyAlert, alert_id)
    if alert is None or alert.trip_id != trip_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "alert not found")
    if alert.acknowledged_at is None:
        alert.acknowledged_at = datetime.now(tz=timezone.utc)
        await session.commit()
        await session.refresh(alert)
    return SafetyAlertOut.model_validate(alert)

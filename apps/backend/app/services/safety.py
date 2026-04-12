"""Server-side detection rules for safety alerts.

Three of the five alert kinds are evaluated server-side from the
incoming WS frames (stranded, speed, fatigue). The other two (sos,
crash) come from the device — the server just persists them and
fans them out via Redis pub/sub.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..models.safety import SafetyAlert

# Tunables
SPEED_LIMIT_KMH = 110
FATIGUE_DRIVE_HOURS = 2.5
STRANDED_BATTERY_THRESHOLD = 10
STRANDED_STILL_MINUTES = 15
ALERT_DEDUPE_MINUTES = 10


async def maybe_emit_speed(
    session: AsyncSession,
    trip_id: uuid.UUID,
    user_id: uuid.UUID,
    speed_mps: float | None,
) -> dict[str, Any] | None:
    if speed_mps is None:
        return None
    speed_kmh = speed_mps * 3.6
    if speed_kmh < SPEED_LIMIT_KMH:
        return None
    if await _is_recently_alerted(session, trip_id, user_id, "speed"):
        return None
    alert = SafetyAlert(
        trip_id=trip_id,
        user_id=user_id,
        kind="speed",
        severity="warning",
        details={"speed_kmh": round(speed_kmh, 1), "limit_kmh": SPEED_LIMIT_KMH},
    )
    session.add(alert)
    await session.commit()
    await session.refresh(alert)
    return _serialize(alert)


async def maybe_emit_stranded(
    session: AsyncSession,
    trip_id: uuid.UUID,
    user_id: uuid.UUID,
    battery: int | None,
    speed_mps: float | None,
) -> dict[str, Any] | None:
    if battery is None or battery > STRANDED_BATTERY_THRESHOLD:
        return None
    if speed_mps is not None and speed_mps > 0.5:
        return None
    if await _is_recently_alerted(session, trip_id, user_id, "stranded"):
        return None
    alert = SafetyAlert(
        trip_id=trip_id,
        user_id=user_id,
        kind="stranded",
        severity="warning",
        details={"battery_pct": battery},
    )
    session.add(alert)
    await session.commit()
    await session.refresh(alert)
    return _serialize(alert)


async def record_device_alert(
    session: AsyncSession,
    *,
    trip_id: uuid.UUID,
    user_id: uuid.UUID,
    kind: str,
    severity: str,
    details: dict[str, Any] | None = None,
) -> dict[str, Any]:
    alert = SafetyAlert(
        trip_id=trip_id,
        user_id=user_id,
        kind=kind,
        severity=severity,
        details=details or {},
    )
    session.add(alert)
    await session.commit()
    await session.refresh(alert)
    return _serialize(alert)


async def _is_recently_alerted(
    session: AsyncSession,
    trip_id: uuid.UUID,
    user_id: uuid.UUID,
    kind: str,
) -> bool:
    cutoff = datetime.now(tz=timezone.utc) - timedelta(minutes=ALERT_DEDUPE_MINUTES)
    recent = await session.scalar(
        select(SafetyAlert)
        .where(
            SafetyAlert.trip_id == trip_id,
            SafetyAlert.user_id == user_id,
            SafetyAlert.kind == kind,
            SafetyAlert.created_at > cutoff,
        )
        .order_by(desc(SafetyAlert.created_at))
        .limit(1)
    )
    return recent is not None


def _serialize(alert: SafetyAlert) -> dict[str, Any]:
    return {
        "type": "safety",
        "alert_id": str(alert.id),
        "kind": alert.kind,
        "severity": alert.severity,
        "user_id": str(alert.user_id),
        "details": alert.details,
        "created_at": alert.created_at.isoformat(),
    }

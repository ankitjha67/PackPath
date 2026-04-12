"""Trip recap endpoint."""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import require_trip_member
from ..models.trip import TripMember
from ..services.recap import compute_recap

router = APIRouter(prefix="/trips/{trip_id}/recap", tags=["recap"])


@router.get("")
async def get_recap(
    trip_id: uuid.UUID,
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> dict:
    return await compute_recap(session, trip_id)

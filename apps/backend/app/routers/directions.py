"""Server-side proxy for routing.

Why proxy: keeps every provider's secret token off-device, enforces trip
membership, and gives us a single place to switch providers (Mapbox /
Google / Mappls / HERE / TomTom / OSRM) and chain fallbacks.
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from ..deps import require_trip_member
from ..models.trip import TripMember
from ..services.maps import (
    Coordinate,
    MapsProviderError,
    NoRouteFoundError,
    RouteProfile,
)
from ..services.maps.registry import get_directions

router = APIRouter(prefix="/trips/{trip_id}/directions", tags=["directions"])


class _Coordinate(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)


class DirectionsRequest(BaseModel):
    profile: str = Field(default="driving", pattern="^(driving|walking|cycling)$")
    coordinates: list[_Coordinate] = Field(min_length=2, max_length=25)


class DirectionsResponse(BaseModel):
    distance_m: float
    duration_s: float
    geometry: dict
    provider: str


@router.post("", response_model=DirectionsResponse)
async def request_directions(
    trip_id: uuid.UUID,
    payload: DirectionsRequest,
    _: TripMember = Depends(require_trip_member),
) -> DirectionsResponse:
    coords = [Coordinate(lat=c.lat, lng=c.lng) for c in payload.coordinates]
    profile = RouteProfile(payload.profile)
    try:
        result = await get_directions(coords, profile=profile)
    except NoRouteFoundError as exc:
        raise HTTPException(status.HTTP_404_NOT_FOUND, str(exc)) from exc
    except MapsProviderError as exc:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, str(exc)) from exc
    return DirectionsResponse(
        distance_m=result.distance_m,
        duration_s=result.duration_s,
        geometry=result.geometry,
        provider=result.provider,
    )

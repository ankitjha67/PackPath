"""Server-side proxy for Mapbox Directions.

Why proxy: keeps the Mapbox secret token off-device, enforces trip membership,
and gives us a place to cache identical route requests later.
"""

from __future__ import annotations

import uuid

import httpx
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from ..config import get_settings
from ..deps import require_trip_member
from ..models.trip import TripMember

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
    geometry: dict  # GeoJSON LineString


@router.post("", response_model=DirectionsResponse)
async def request_directions(
    trip_id: uuid.UUID,
    payload: DirectionsRequest,
    _: TripMember = Depends(require_trip_member),
) -> DirectionsResponse:
    settings = get_settings()
    if not settings.mapbox_server_token:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "MAPBOX_SERVER_TOKEN is not configured",
        )

    coords = ";".join(f"{c.lng},{c.lat}" for c in payload.coordinates)
    url = (
        f"https://api.mapbox.com/directions/v5/mapbox/{payload.profile}/{coords}"
    )
    params = {
        "access_token": settings.mapbox_server_token,
        "geometries": "geojson",
        "overview": "full",
        "alternatives": "false",
    }
    async with httpx.AsyncClient(timeout=10) as client:
        r = await client.get(url, params=params)
    if r.status_code != 200:
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY, f"mapbox directions failed: {r.text}"
        )
    data = r.json()
    routes = data.get("routes") or []
    if not routes:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "no route found")
    route = routes[0]
    return DirectionsResponse(
        distance_m=float(route["distance"]),
        duration_s=float(route["duration"]),
        geometry=route["geometry"],
    )

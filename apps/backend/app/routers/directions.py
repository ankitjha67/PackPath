"""Server-side proxy for routing + smart routing add-ons.

Why proxy: keeps every provider's secret token off-device, enforces trip
membership, and gives us a single place to switch providers (Mapbox /
Google / Mappls / HERE / TomTom / OSRM) and chain fallbacks. The same
router exposes the cost / weather / elevation enrichments built on top.
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from ..deps import require_trip_member
from ..models.trip import TripMember
from ..services.cost import CostEstimate, estimate_cost
from ..services.elevation import profile as elevation_profile
from ..services.maps import (
    Coordinate,
    MapsProviderError,
    NoRouteFoundError,
    RouteProfile,
)
from ..services.maps.registry import get_directions
from ..services.weather import along_route as weather_along_route

router = APIRouter(prefix="/trips/{trip_id}/directions", tags=["directions"])


class _Coordinate(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)


class DirectionsRequest(BaseModel):
    profile: str = Field(default="driving", pattern="^(driving|walking|cycling)$")
    coordinates: list[_Coordinate] = Field(min_length=2, max_length=25)
    region: str = Field(default="IN", pattern="^[A-Z]{2}$")
    vehicle: str = Field(default="hatchback")
    enrich_cost: bool = False
    enrich_weather: bool = False
    enrich_elevation: bool = False


class CostBlock(BaseModel):
    fuel_cents: int
    toll_cents: int
    total_cents: int
    fuel_litres: float
    currency: str


class WeatherBlock(BaseModel):
    lat: float
    lng: float
    temperature_c: float
    condition: str
    wind_kmh: float
    pop: float


class ElevationBlock(BaseModel):
    samples: list[tuple[float, float, float]]
    min_m: float
    max_m: float
    gain_m: float
    loss_m: float


class DirectionsResponse(BaseModel):
    distance_m: float
    duration_s: float
    geometry: dict
    provider: str
    cost: CostBlock | None = None
    weather: list[WeatherBlock] | None = None
    elevation: ElevationBlock | None = None


def _coords_from_geometry(geometry: dict) -> list[tuple[float, float]]:
    if geometry.get("type") != "LineString":
        return []
    return [(float(c[1]), float(c[0])) for c in geometry.get("coordinates", [])]


def _serialize_cost(estimate: CostEstimate) -> CostBlock:
    return CostBlock(
        fuel_cents=estimate.fuel_cents,
        toll_cents=estimate.toll_cents,
        total_cents=estimate.total_cents,
        fuel_litres=estimate.fuel_litres,
        currency=estimate.currency,
    )


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

    response = DirectionsResponse(
        distance_m=result.distance_m,
        duration_s=result.duration_s,
        geometry=result.geometry,
        provider=result.provider,
    )

    if payload.enrich_cost:
        response.cost = _serialize_cost(
            estimate_cost(
                distance_m=result.distance_m,
                region=payload.region,
                vehicle=payload.vehicle,
            )
        )
    polyline_coords = _coords_from_geometry(result.geometry)
    if payload.enrich_weather and polyline_coords:
        samples = await weather_along_route(polyline_coords)
        response.weather = [
            WeatherBlock(
                lat=s.lat,
                lng=s.lng,
                temperature_c=s.temperature_c,
                condition=s.condition,
                wind_kmh=s.wind_kmh,
                pop=s.pop,
            )
            for s in samples
        ]
    if payload.enrich_elevation and polyline_coords:
        prof = await elevation_profile(polyline_coords)
        response.elevation = ElevationBlock(
            samples=prof.samples,
            min_m=prof.min_m,
            max_m=prof.max_m,
            gain_m=prof.gain_m,
            loss_m=prof.loss_m,
        )
    return response


@router.post("/cost", response_model=CostBlock)
async def estimate_route_cost(
    trip_id: uuid.UUID,
    payload: DirectionsRequest,
    _: TripMember = Depends(require_trip_member),
) -> CostBlock:
    """Quick cost-only path that skips the geometry/weather work when the
    client only wants the bottom-line number."""
    coords = [Coordinate(lat=c.lat, lng=c.lng) for c in payload.coordinates]
    try:
        result = await get_directions(coords, profile=RouteProfile(payload.profile))
    except NoRouteFoundError as exc:
        raise HTTPException(status.HTTP_404_NOT_FOUND, str(exc)) from exc
    except MapsProviderError as exc:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, str(exc)) from exc
    return _serialize_cost(
        estimate_cost(
            distance_m=result.distance_m,
            region=payload.region,
            vehicle=payload.vehicle,
        )
    )

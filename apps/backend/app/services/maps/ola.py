"""Ola Maps Directions provider (India-tuned routing).

Ola's Directions API returns the route geometry as an encoded polyline
(Google precision-5 encoding), which we decode to a GeoJSON LineString so the
response matches every other provider in this package.
"""

from __future__ import annotations

from typing import Any, Sequence

import httpx

from ...config import get_settings
from .base import (
    BaseMapsProvider,
    Coordinate,
    MapsProviderError,
    NoRouteFoundError,
    RouteProfile,
    RouteResult,
)

_DIRECTIONS_URL = "https://api.olamaps.io/routing/v1/directions"


def _decode_polyline(encoded: str) -> list[list[float]]:
    """Decode a Google/Ola precision-5 encoded polyline to [lng, lat] pairs."""
    coords: list[list[float]] = []
    index = 0
    lat = 0
    lng = 0
    length = len(encoded)
    while index < length:
        for is_lng in (False, True):
            shift = 0
            result = 0
            while True:
                if index >= length:
                    return coords
                b = ord(encoded[index]) - 63
                index += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20:
                    break
            delta = ~(result >> 1) if (result & 1) else (result >> 1)
            if is_lng:
                lng += delta
            else:
                lat += delta
        # GeoJSON order is [lng, lat].
        coords.append([lng / 1e5, lat / 1e5])
    return coords


class OlaMapsProvider(BaseMapsProvider):
    name = "ola"

    def is_configured(self) -> bool:
        return bool(get_settings().ola_maps_api_key)

    async def directions(
        self,
        coordinates: Sequence[Coordinate],
        *,
        profile: RouteProfile = RouteProfile.DRIVING,
    ) -> RouteResult:
        key = get_settings().ola_maps_api_key
        if not key:
            raise MapsProviderError("ola: no api key configured")
        if len(coordinates) < 2:
            raise MapsProviderError("ola: need at least origin and destination")

        origin = coordinates[0]
        destination = coordinates[-1]
        params: dict[str, Any] = {
            "origin": f"{origin.lat},{origin.lng}",
            "destination": f"{destination.lat},{destination.lng}",
            "api_key": key,
        }
        # Intermediate stops, pipe-separated "lat,lng|lat,lng".
        middle = coordinates[1:-1]
        if middle:
            params["waypoints"] = "|".join(f"{c.lat},{c.lng}" for c in middle)

        # Ola's directions endpoint is a POST with the inputs as query params
        # and an empty body.
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.post(_DIRECTIONS_URL, params=params)
        if r.status_code != 200:
            raise MapsProviderError(f"ola {r.status_code}: {r.text[:200]}")

        body = r.json()
        routes = body.get("routes") or []
        if not routes:
            raise NoRouteFoundError("ola returned no routes")
        route = routes[0]

        legs = route.get("legs") or []
        distance_m = float(sum(leg.get("distance", 0) or 0 for leg in legs))
        duration_s = float(sum(leg.get("duration", 0) or 0 for leg in legs))

        encoded = route.get("overview_polyline") or ""
        line = _decode_polyline(encoded) if encoded else []
        if not line:
            raise NoRouteFoundError("ola route had no geometry")

        return RouteResult(
            distance_m=distance_m,
            duration_s=duration_s,
            geometry={"type": "LineString", "coordinates": line},
            provider=self.name,
        )

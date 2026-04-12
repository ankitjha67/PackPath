"""Google Maps Directions API provider.

Google returns route geometry as an encoded polyline (Google's algorithm,
not GeoJSON). We decode it into a GeoJSON LineString in-process so the
mobile client gets the same shape regardless of provider.
"""

from __future__ import annotations

from typing import Sequence

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

_PROFILE_MAP = {
    RouteProfile.DRIVING: "driving",
    RouteProfile.WALKING: "walking",
    RouteProfile.CYCLING: "bicycling",
}


def _decode_polyline(encoded: str) -> list[list[float]]:
    """Decode a Google Maps encoded polyline into [[lng, lat], ...] pairs."""
    coords: list[list[float]] = []
    index = 0
    lat = 0
    lng = 0
    while index < len(encoded):
        for target in (0, 1):
            shift = 0
            result = 0
            while True:
                if index >= len(encoded):
                    return coords
                b = ord(encoded[index]) - 63
                index += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20:
                    break
            delta = ~(result >> 1) if (result & 1) else (result >> 1)
            if target == 0:
                lat += delta
            else:
                lng += delta
        coords.append([lng / 1e5, lat / 1e5])
    return coords


class GoogleMapsProvider(BaseMapsProvider):
    name = "google"

    def is_configured(self) -> bool:
        return bool(get_settings().google_maps_api_key)

    async def directions(
        self,
        coordinates: Sequence[Coordinate],
        *,
        profile: RouteProfile = RouteProfile.DRIVING,
    ) -> RouteResult:
        api_key = get_settings().google_maps_api_key
        if len(coordinates) < 2:
            raise MapsProviderError("need at least 2 coordinates")
        origin = coordinates[0]
        destination = coordinates[-1]
        waypoints = coordinates[1:-1]
        params: dict[str, str] = {
            "origin": f"{origin.lat},{origin.lng}",
            "destination": f"{destination.lat},{destination.lng}",
            "mode": _PROFILE_MAP[profile],
            "key": api_key,
        }
        if waypoints:
            params["waypoints"] = "|".join(
                f"{c.lat},{c.lng}" for c in waypoints
            )

        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.get(
                "https://maps.googleapis.com/maps/api/directions/json",
                params=params,
            )
        if r.status_code != 200:
            raise MapsProviderError(f"google {r.status_code}: {r.text[:200]}")
        data = r.json()
        if data.get("status") != "OK":
            raise NoRouteFoundError(
                f"google status={data.get('status')} {data.get('error_message','')}"
            )
        routes = data.get("routes") or []
        if not routes:
            raise NoRouteFoundError("google returned no routes")
        route = routes[0]
        legs = route.get("legs", [])
        distance_m = sum(leg["distance"]["value"] for leg in legs)
        duration_s = sum(leg["duration"]["value"] for leg in legs)
        encoded = route["overview_polyline"]["points"]
        coords = _decode_polyline(encoded)
        return RouteResult(
            distance_m=float(distance_m),
            duration_s=float(duration_s),
            geometry={"type": "LineString", "coordinates": coords},
            provider=self.name,
        )

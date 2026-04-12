"""TomTom Routing API provider.

TomTom returns route geometry as a JSON list of `{latitude, longitude}`
points so no decoding is needed.
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
    RouteProfile.DRIVING: "car",
    RouteProfile.WALKING: "pedestrian",
    RouteProfile.CYCLING: "bicycle",
}


class TomTomProvider(BaseMapsProvider):
    name = "tomtom"

    def is_configured(self) -> bool:
        return bool(get_settings().tomtom_api_key)

    async def directions(
        self,
        coordinates: Sequence[Coordinate],
        *,
        profile: RouteProfile = RouteProfile.DRIVING,
    ) -> RouteResult:
        if len(coordinates) < 2:
            raise MapsProviderError("need at least 2 coordinates")
        api_key = get_settings().tomtom_api_key
        coord_str = ":".join(f"{c.lat},{c.lng}" for c in coordinates)
        url = (
            f"https://api.tomtom.com/routing/1/calculateRoute/{coord_str}/json"
        )
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.get(
                url,
                params={
                    "key": api_key,
                    "travelMode": _PROFILE_MAP[profile],
                    "routeRepresentation": "polyline",
                    "computeBestOrder": "false",
                    "traffic": "true",
                },
            )
        if r.status_code != 200:
            raise MapsProviderError(f"tomtom {r.status_code}: {r.text[:200]}")
        data = r.json()
        routes = data.get("routes") or []
        if not routes:
            raise NoRouteFoundError("tomtom returned no routes")
        route = routes[0]
        summary = route.get("summary") or {}
        coords: list[list[float]] = []
        for leg in route.get("legs", []):
            for point in leg.get("points", []):
                coords.append(
                    [float(point["longitude"]), float(point["latitude"])]
                )
        return RouteResult(
            distance_m=float(summary.get("lengthInMeters", 0)),
            duration_s=float(summary.get("travelTimeInSeconds", 0)),
            geometry={"type": "LineString", "coordinates": coords},
            provider=self.name,
        )

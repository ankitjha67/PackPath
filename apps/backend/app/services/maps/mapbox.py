"""Mapbox Directions v5 provider."""

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


class MapboxProvider(BaseMapsProvider):
    name = "mapbox"

    def is_configured(self) -> bool:
        return bool(get_settings().mapbox_server_token)

    async def directions(
        self,
        coordinates: Sequence[Coordinate],
        *,
        profile: RouteProfile = RouteProfile.DRIVING,
    ) -> RouteResult:
        token = get_settings().mapbox_server_token
        coords = ";".join(f"{c.lng},{c.lat}" for c in coordinates)
        url = f"https://api.mapbox.com/directions/v5/mapbox/{profile.value}/{coords}"
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.get(
                url,
                params={
                    "access_token": token,
                    "geometries": "geojson",
                    "overview": "full",
                    "alternatives": "false",
                },
            )
        if r.status_code != 200:
            raise MapsProviderError(f"mapbox {r.status_code}: {r.text[:200]}")
        routes = r.json().get("routes") or []
        if not routes:
            raise NoRouteFoundError("mapbox returned no routes")
        route = routes[0]
        return RouteResult(
            distance_m=float(route["distance"]),
            duration_s=float(route["duration"]),
            geometry=route["geometry"],
            provider=self.name,
        )

"""OSRM provider.

OSRM is the routing engine that powers most open-source routing stacks
(it's also what Mapbox runs internally). The public demo at
`router.project-osrm.org` is fine for development and small deployments;
production should self-host an OSRM container with the OSM extract for
the regions of interest.
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
    RouteProfile.CYCLING: "cycling",
}


class OsrmProvider(BaseMapsProvider):
    name = "osrm"

    def is_configured(self) -> bool:
        # Always configured — defaults to the public demo URL.
        return True

    async def directions(
        self,
        coordinates: Sequence[Coordinate],
        *,
        profile: RouteProfile = RouteProfile.DRIVING,
    ) -> RouteResult:
        if len(coordinates) < 2:
            raise MapsProviderError("need at least 2 coordinates")
        base = get_settings().osrm_base_url.rstrip("/")
        coord_str = ";".join(f"{c.lng},{c.lat}" for c in coordinates)
        url = f"{base}/route/v1/{_PROFILE_MAP[profile]}/{coord_str}"
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.get(
                url,
                params={
                    "geometries": "geojson",
                    "overview": "full",
                    "alternatives": "false",
                    "steps": "false",
                },
            )
        if r.status_code != 200:
            raise MapsProviderError(f"osrm {r.status_code}: {r.text[:200]}")
        data = r.json()
        if data.get("code") != "Ok":
            raise NoRouteFoundError(
                f"osrm code={data.get('code')} {data.get('message','')}"
            )
        routes = data.get("routes") or []
        if not routes:
            raise NoRouteFoundError("osrm returned no routes")
        route = routes[0]
        return RouteResult(
            distance_m=float(route["distance"]),
            duration_s=float(route["duration"]),
            geometry=route["geometry"],
            provider=self.name,
        )

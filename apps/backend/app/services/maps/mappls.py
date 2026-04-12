"""Mappls (formerly MapmyIndia) routing provider.

Mappls is the highest-quality map data inside India. It offers two
relevant routing endpoints:
  * `route_adv` — REST routing with full geometry as encoded polyline
  * `directions` — turn-by-turn (used by their web SDK)

Auth is OAuth client-credentials: exchange `MAPPLS_CLIENT_ID` /
`MAPPLS_CLIENT_SECRET` for a short-lived bearer token, then call the
routing endpoint with `Authorization: Bearer <token>`. We cache the
token in-process until ~60s before expiry.
"""

from __future__ import annotations

import asyncio
import time
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
from .google import _decode_polyline  # Mappls uses the same encoded polyline

_PROFILE_MAP = {
    RouteProfile.DRIVING: "driving",
    RouteProfile.WALKING: "walking",
    RouteProfile.CYCLING: "biking",
}


class MapplsProvider(BaseMapsProvider):
    name = "mappls"

    def __init__(self) -> None:
        self._token: str | None = None
        self._token_expires_at: float = 0.0
        self._token_lock = asyncio.Lock()

    def is_configured(self) -> bool:
        s = get_settings()
        return bool(s.mappls_client_id and s.mappls_client_secret)

    async def _get_token(self) -> str:
        async with self._token_lock:
            now = time.monotonic()
            if self._token and now < self._token_expires_at - 60:
                return self._token
            s = get_settings()
            async with httpx.AsyncClient(timeout=10) as client:
                r = await client.post(
                    "https://outpost.mappls.com/api/security/oauth/token",
                    data={
                        "grant_type": "client_credentials",
                        "client_id": s.mappls_client_id,
                        "client_secret": s.mappls_client_secret,
                    },
                )
            if r.status_code != 200:
                raise MapsProviderError(
                    f"mappls oauth {r.status_code}: {r.text[:200]}"
                )
            data = r.json()
            self._token = data["access_token"]
            self._token_expires_at = now + float(data.get("expires_in", 3600))
            return self._token

    async def directions(
        self,
        coordinates: Sequence[Coordinate],
        *,
        profile: RouteProfile = RouteProfile.DRIVING,
    ) -> RouteResult:
        if len(coordinates) < 2:
            raise MapsProviderError("need at least 2 coordinates")
        token = await self._get_token()
        coord_str = ";".join(f"{c.lng},{c.lat}" for c in coordinates)
        url = (
            "https://apis.mappls.com/advancedmaps/v1/"
            f"{get_settings().mappls_rest_key or token}/route_adv/"
            f"{_PROFILE_MAP[profile]}/{coord_str}"
        )
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.get(
                url,
                params={
                    "geometries": "polyline",
                    "overview": "full",
                    "alternatives": "false",
                    "steps": "false",
                },
                headers={"Authorization": f"Bearer {token}"},
            )
        if r.status_code != 200:
            raise MapsProviderError(f"mappls {r.status_code}: {r.text[:200]}")
        data = r.json()
        routes = data.get("routes") or []
        if not routes:
            raise NoRouteFoundError("mappls returned no routes")
        route = routes[0]
        coords = _decode_polyline(route.get("geometry", ""))
        return RouteResult(
            distance_m=float(route.get("distance", 0)),
            duration_s=float(route.get("duration", 0)),
            geometry={"type": "LineString", "coordinates": coords},
            provider=self.name,
        )

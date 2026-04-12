"""HERE Routing v8 provider.

HERE returns route geometry as a flexible-polyline string. We use a
minimal in-process decoder so we don't pull in another dependency.
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


def _decode_flexible_polyline(encoded: str) -> list[list[float]]:
    """Minimal HERE flexible-polyline decoder.

    Spec: https://github.com/heremaps/flexible-polyline
    Returns [[lng, lat], ...]. Ignores third-dimension if present.
    """
    if not encoded:
        return []
    decoder = _FlexDecoder(encoded)
    header = decoder.next_unsigned()
    version = header & 15
    if version != 1:
        raise MapsProviderError(f"unsupported flexible-polyline version {version}")
    second_header = decoder.next_unsigned()
    precision = second_header & 15
    third_dim = (second_header >> 4) & 7
    third_dim_precision = (second_header >> 7) & 15
    factor = 10**precision
    third_factor = 10**third_dim_precision

    coords: list[list[float]] = []
    last_lat = 0
    last_lng = 0
    last_z = 0
    while decoder.has_more():
        last_lat += decoder.next_signed()
        last_lng += decoder.next_signed()
        if third_dim:
            last_z += decoder.next_signed()
            _ = last_z / third_factor  # consumed but ignored for v1
        coords.append([last_lng / factor, last_lat / factor])
    return coords


class _FlexDecoder:
    _ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

    def __init__(self, encoded: str) -> None:
        self.s = encoded
        self.i = 0
        self._lookup = {ch: idx for idx, ch in enumerate(self._ALPHABET)}

    def has_more(self) -> bool:
        return self.i < len(self.s)

    def next_unsigned(self) -> int:
        result = 0
        shift = 0
        while True:
            if self.i >= len(self.s):
                raise MapsProviderError("flexible-polyline truncated")
            b = self._lookup[self.s[self.i]]
            self.i += 1
            result |= (b & 0x1F) << shift
            if b < 0x20:
                return result
            shift += 5

    def next_signed(self) -> int:
        u = self.next_unsigned()
        return ~(u >> 1) if (u & 1) else (u >> 1)


class HereMapsProvider(BaseMapsProvider):
    name = "here"

    def is_configured(self) -> bool:
        return bool(get_settings().here_api_key)

    async def directions(
        self,
        coordinates: Sequence[Coordinate],
        *,
        profile: RouteProfile = RouteProfile.DRIVING,
    ) -> RouteResult:
        if len(coordinates) < 2:
            raise MapsProviderError("need at least 2 coordinates")
        api_key = get_settings().here_api_key
        params: dict[str, str] = {
            "transportMode": _PROFILE_MAP[profile],
            "origin": f"{coordinates[0].lat},{coordinates[0].lng}",
            "destination": f"{coordinates[-1].lat},{coordinates[-1].lng}",
            "return": "polyline,summary",
            "apikey": api_key,
        }
        if len(coordinates) > 2:
            via = [f"{c.lat},{c.lng}" for c in coordinates[1:-1]]
            params["via"] = "!".join(via)

        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.get(
                "https://router.hereapi.com/v8/routes", params=params
            )
        if r.status_code != 200:
            raise MapsProviderError(f"here {r.status_code}: {r.text[:200]}")
        data = r.json()
        routes = data.get("routes") or []
        if not routes:
            raise NoRouteFoundError("here returned no routes")
        sections = routes[0].get("sections") or []
        if not sections:
            raise NoRouteFoundError("here route had no sections")
        coords: list[list[float]] = []
        distance = 0.0
        duration = 0.0
        for section in sections:
            polyline = section.get("polyline")
            if polyline:
                coords.extend(_decode_flexible_polyline(polyline))
            summary = section.get("summary") or {}
            distance += float(summary.get("length", 0))
            duration += float(summary.get("duration", 0))
        return RouteResult(
            distance_m=distance,
            duration_s=duration,
            geometry={"type": "LineString", "coordinates": coords},
            provider=self.name,
        )

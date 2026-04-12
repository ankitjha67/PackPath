"""Elevation samples along a polyline.

Uses Open-Elevation (free, public) when reachable. Falls back to a
simple sinusoidal mock so the rest of the app keeps working without
network. Returns metres above sea level.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Sequence

import httpx


@dataclass(frozen=True)
class ElevationProfile:
    samples: list[tuple[float, float, float]]  # lat, lng, elevation_m
    min_m: float
    max_m: float
    gain_m: float
    loss_m: float

    @classmethod
    def from_samples(
        cls, samples: list[tuple[float, float, float]]
    ) -> "ElevationProfile":
        if not samples:
            return cls(samples=[], min_m=0, max_m=0, gain_m=0, loss_m=0)
        elevations = [s[2] for s in samples]
        gain = 0.0
        loss = 0.0
        for prev, cur in zip(elevations, elevations[1:]):
            delta = cur - prev
            if delta > 0:
                gain += delta
            else:
                loss += -delta
        return cls(
            samples=samples,
            min_m=min(elevations),
            max_m=max(elevations),
            gain_m=round(gain, 1),
            loss_m=round(loss, 1),
        )


async def profile(
    coordinates: Sequence[tuple[float, float]],
    *,
    samples: int = 32,
) -> ElevationProfile:
    if not coordinates:
        return ElevationProfile.from_samples([])
    if len(coordinates) > samples:
        step = len(coordinates) / samples
        picked = [coordinates[int(i * step)] for i in range(samples)]
    else:
        picked = list(coordinates)
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.post(
                "https://api.open-elevation.com/api/v1/lookup",
                json={
                    "locations": [
                        {"latitude": lat, "longitude": lng}
                        for lat, lng in picked
                    ]
                },
            )
            if r.status_code == 200:
                data = r.json().get("results") or []
                return ElevationProfile.from_samples(
                    [
                        (
                            float(row["latitude"]),
                            float(row["longitude"]),
                            float(row["elevation"]),
                        )
                        for row in data
                    ]
                )
    except httpx.HTTPError:
        pass
    # Fallback: deterministic mock based on lat
    return ElevationProfile.from_samples(
        [(lat, lng, _mock_elevation(lat, lng)) for lat, lng in picked]
    )


def _mock_elevation(lat: float, lng: float) -> float:
    return 200 + 80 * math.sin(lat * 0.5) + 40 * math.cos(lng * 0.7)

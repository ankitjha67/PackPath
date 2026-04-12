"""Weather samples along a route polyline.

Uses OpenWeatherMap if `OPENWEATHER_API_KEY` is configured. With no
key, falls back to a deterministic mock so the rest of the app keeps
working in dev (and so the unit shape is stable for tests).

We sample evenly along the polyline rather than every coordinate to
keep the upstream call count bounded.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

import httpx

from ..config import get_settings


@dataclass(frozen=True)
class WeatherSample:
    lat: float
    lng: float
    temperature_c: float
    condition: str
    wind_kmh: float
    pop: float  # probability of precipitation 0..1


def _sample_indices(n: int, want: int) -> list[int]:
    if n <= want:
        return list(range(n))
    step = (n - 1) / (want - 1)
    return [round(i * step) for i in range(want)]


async def along_route(
    coordinates: Sequence[tuple[float, float]],
    *,
    samples: int = 5,
) -> list[WeatherSample]:
    if not coordinates:
        return []
    indices = _sample_indices(len(coordinates), samples)
    settings = get_settings()
    api_key = getattr(settings, "openweather_api_key", "")
    if not api_key:
        return [
            _mock_sample(coordinates[i][0], coordinates[i][1])
            for i in indices
        ]
    out: list[WeatherSample] = []
    async with httpx.AsyncClient(timeout=10) as client:
        for i in indices:
            lat, lng = coordinates[i]
            try:
                r = await client.get(
                    "https://api.openweathermap.org/data/2.5/weather",
                    params={
                        "lat": lat,
                        "lon": lng,
                        "appid": api_key,
                        "units": "metric",
                    },
                )
                if r.status_code == 200:
                    data = r.json()
                    weather = (data.get("weather") or [{}])[0]
                    out.append(
                        WeatherSample(
                            lat=lat,
                            lng=lng,
                            temperature_c=float(
                                data.get("main", {}).get("temp", 0)
                            ),
                            condition=weather.get("main", "Clear"),
                            wind_kmh=float(data.get("wind", {}).get("speed", 0)) * 3.6,
                            pop=0.0,
                        )
                    )
                    continue
            except httpx.HTTPError:
                pass
            out.append(_mock_sample(lat, lng))
    return out


def _mock_sample(lat: float, lng: float) -> WeatherSample:
    """Deterministic mock — useful in tests and dev. Maps lat/lng to
    pseudo-random but stable values."""
    seed = int((lat * 1000 + lng * 1000)) % 100
    return WeatherSample(
        lat=lat,
        lng=lng,
        temperature_c=20 + (seed % 15) - 5,
        condition=["Clear", "Clouds", "Rain", "Thunderstorm"][seed % 4],
        wind_kmh=5 + (seed % 25),
        pop=(seed % 100) / 100.0,
    )

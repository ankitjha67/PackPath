"""Provider registry + resolver.

The default provider is picked from `MAPS_PROVIDER` (env). When that's
unset, we pick the first configured provider in this preference order so
the app keeps working in any environment that has *any* maps key:

    mappls → google → here → mapbox → tomtom → osrm

`MAPS_FALLBACK_PROVIDERS=mapbox,osrm` lets us chain fallbacks: if the
default fails or returns NoRouteFoundError, we try each fallback in
order before giving up.
"""

from __future__ import annotations

from functools import lru_cache
from typing import Iterable

from loguru import logger

from ...config import get_settings
from .base import (
    BaseMapsProvider,
    Coordinate,
    MapsProviderError,
    NoRouteFoundError,
    RouteProfile,
    RouteResult,
)
from .google import GoogleMapsProvider
from .here import HereMapsProvider
from .mapbox import MapboxProvider
from .mappls import MapplsProvider
from .osrm import OsrmProvider
from .tomtom import TomTomProvider

_PREFERENCE = ("mappls", "google", "here", "mapbox", "tomtom", "osrm")


@lru_cache(maxsize=1)
def _instances() -> dict[str, BaseMapsProvider]:
    return {
        "mapbox": MapboxProvider(),
        "google": GoogleMapsProvider(),
        "mappls": MapplsProvider(),
        "here": HereMapsProvider(),
        "tomtom": TomTomProvider(),
        "osrm": OsrmProvider(),
    }


def list_providers() -> list[dict]:
    """Used by `GET /maps/providers` so the mobile client can show what's
    available without holding any secrets."""
    return [
        {"name": p.name, "configured": p.is_configured()}
        for p in _instances().values()
    ]


def get_provider(name: str) -> BaseMapsProvider:
    instances = _instances()
    if name not in instances:
        raise KeyError(f"unknown maps provider: {name}")
    return instances[name]


def default_provider() -> BaseMapsProvider:
    settings = get_settings()
    instances = _instances()
    if settings.maps_provider:
        try:
            return get_provider(settings.maps_provider)
        except KeyError:
            logger.warning(
                "Unknown MAPS_PROVIDER={}, falling back", settings.maps_provider
            )
    for name in _PREFERENCE:
        provider = instances[name]
        if provider.is_configured():
            return provider
    return instances["osrm"]  # always configured


def fallback_chain() -> list[BaseMapsProvider]:
    settings = get_settings()
    if not settings.maps_fallback_providers:
        return []
    out: list[BaseMapsProvider] = []
    for name in settings.maps_fallback_providers:
        try:
            provider = get_provider(name.strip())
        except KeyError:
            continue
        if provider.is_configured():
            out.append(provider)
    return out


async def get_directions(
    coordinates: Iterable[Coordinate],
    *,
    profile: RouteProfile = RouteProfile.DRIVING,
) -> RouteResult:
    """Resolve directions through the default provider, falling back
    through `MAPS_FALLBACK_PROVIDERS` on failure or NoRouteFoundError."""
    coords = list(coordinates)
    candidates: list[BaseMapsProvider] = [default_provider(), *fallback_chain()]
    last_error: Exception | None = None
    for provider in candidates:
        if not provider.is_configured():
            continue
        try:
            return await provider.directions(coords, profile=profile)
        except NoRouteFoundError as exc:
            logger.info("{} found no route, trying next", provider.name)
            last_error = exc
            continue
        except MapsProviderError as exc:
            logger.warning("{} failed: {}", provider.name, exc)
            last_error = exc
            continue
    if last_error is not None:
        raise last_error
    raise MapsProviderError("no maps provider is configured")

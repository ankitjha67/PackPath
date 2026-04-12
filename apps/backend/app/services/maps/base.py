"""Common types for the maps provider abstraction."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Any, Sequence


class RouteProfile(str, Enum):
    DRIVING = "driving"
    WALKING = "walking"
    CYCLING = "cycling"


@dataclass(frozen=True)
class Coordinate:
    lat: float
    lng: float


@dataclass(frozen=True)
class RouteResult:
    """Provider-agnostic route response.

    `geometry` is always a GeoJSON LineString dict so the mobile client
    doesn't need to know which provider answered. Distance is in meters,
    duration in seconds — same as Mapbox.
    """

    distance_m: float
    duration_s: float
    geometry: dict[str, Any]
    provider: str


class MapsProviderError(RuntimeError):
    """Generic upstream failure (network, 4xx/5xx, parse error)."""


class NoRouteFoundError(MapsProviderError):
    """The provider responded but couldn't find a route between the points."""


class BaseMapsProvider:
    """Subclass and override :meth:`directions`. Return a normalized
    :class:`RouteResult` or raise :class:`MapsProviderError`."""

    name: str = "base"

    def is_configured(self) -> bool:  # pragma: no cover - trivial
        return True

    async def directions(
        self,
        coordinates: Sequence[Coordinate],
        *,
        profile: RouteProfile = RouteProfile.DRIVING,
    ) -> RouteResult:
        raise NotImplementedError

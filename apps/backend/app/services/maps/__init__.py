"""Maps provider abstraction.

PackPath supports multiple routing backends so we can pick the best one
per region (Mappls in India, Google globally, OSRM at scale, etc.) and so
we can fall back gracefully when one is rate-limited or returns nothing.

Add a new provider by subclassing :class:`BaseMapsProvider` in this
package and registering it in :func:`get_provider`. Each provider returns
a :class:`RouteResult` with the same shape no matter which API answered.
"""

from __future__ import annotations

from .base import (
    BaseMapsProvider,
    Coordinate,
    MapsProviderError,
    NoRouteFoundError,
    RouteProfile,
    RouteResult,
)
from .registry import default_provider, get_provider, list_providers

__all__ = [
    "BaseMapsProvider",
    "Coordinate",
    "MapsProviderError",
    "NoRouteFoundError",
    "RouteProfile",
    "RouteResult",
    "default_provider",
    "get_provider",
    "list_providers",
]

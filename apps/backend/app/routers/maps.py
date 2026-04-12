"""Public maps provider listing.

The mobile client uses this to render the tile-layer switcher and to
show which routing backend it would actually hit. No secrets ever
leave the server — only `{name, configured}` per provider plus the
resolved default.
"""

from __future__ import annotations

from fastapi import APIRouter
from pydantic import BaseModel

from ..config import get_settings
from ..services.maps.registry import default_provider, list_providers

router = APIRouter(prefix="/maps", tags=["maps"])


class ProviderEntry(BaseModel):
    name: str
    configured: bool


class ProvidersResponse(BaseModel):
    default: str
    fallback_chain: list[str]
    providers: list[ProviderEntry]


@router.get("/providers", response_model=ProvidersResponse)
async def get_providers() -> ProvidersResponse:
    settings = get_settings()
    return ProvidersResponse(
        default=default_provider().name,
        fallback_chain=settings.maps_fallback_providers,
        providers=[ProviderEntry(**p) for p in list_providers()],
    )

"""GET /hazards — NASA EONET hazard fan-out for mobile clients.

The upstream fetch is cached globally in Redis (see eonet_service),
and this router only slices that cache by optional bbox and category
filters before serving. The polling cadence on mobile is 5 minutes
so we rate-limit at 60/minute per IP to leave headroom for screens
that re-watch the provider mid-trip.
"""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Query, Request, status

from ..rate_limit import limiter
from ..schemas.hazard import HazardsResponse
from ..services.eonet_service import (
    EonetUpstreamError,
    fetch_hazards,
    filter_by_bbox,
    filter_by_categories,
)

router = APIRouter(prefix="/hazards", tags=["hazards"])


_VALID_CATEGORIES = {
    "wildfires",
    "severeStorms",
    "volcanoes",
    "seaLakeIce",
    "earthquakes",
    "floods",
    "landslides",
    "drought",
    "dustHaze",
    "manmade",
    "snow",
    "tempExtremes",
    "waterColor",
}


def _parse_bbox(raw: str) -> tuple[float, float, float, float]:
    parts = raw.split(",")
    if len(parts) != 4:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "bbox must be 'south,west,north,east'",
        )
    try:
        south, west, north, east = (float(p) for p in parts)
    except ValueError as exc:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            f"bbox must be four floats: {exc}",
        ) from exc
    if not (-90.0 <= south <= north <= 90.0):
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "bbox south must be <= north and both in [-90, 90]",
        )
    if not (-180.0 <= west <= 180.0 and -180.0 <= east <= 180.0):
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "bbox west/east must be in [-180, 180]",
        )
    return south, west, north, east


def _parse_categories(raw: str | None) -> set[str]:
    if not raw:
        return set()
    requested = {c.strip() for c in raw.split(",") if c.strip()}
    unknown = requested - _VALID_CATEGORIES
    if unknown:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            f"unknown categories: {sorted(unknown)}",
        )
    return requested


@router.get("", response_model=HazardsResponse)
@limiter.limit("60/minute")
async def list_hazards(
    request: Request,
    bbox: str | None = Query(
        default=None,
        description="Optional south,west,north,east bbox filter.",
    ),
    categories: str | None = Query(
        default=None,
        description="Optional comma-separated EONET category ids.",
    ),
) -> HazardsResponse:
    try:
        hazards, cached = await fetch_hazards()
    except EonetUpstreamError as exc:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "error": "eonet_unreachable",
                "message": str(exc),
            },
        ) from exc

    if bbox:
        hazards = filter_by_bbox(hazards, _parse_bbox(bbox))
    wanted = _parse_categories(categories)
    if wanted:
        hazards = filter_by_categories(hazards, wanted)

    return HazardsResponse(
        hazards=hazards,
        cached=cached,
        fetched_at=datetime.now(timezone.utc),
    )

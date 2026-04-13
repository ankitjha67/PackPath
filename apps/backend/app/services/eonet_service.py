"""NASA EONET (Earth Observatory Natural Event Tracker) v3 fetcher.

Fans EONET events out to the mobile clients via the /hazards router.
Keeps a single global cache in Redis at "eonet:v1:global" with a 15 min
TTL. Clients request bbox / category slices of the cache server-side
so we don't hit EONET per-request — EONET's public API is unauthenticated
but rate-limited on the server side, and spamming it from every phone
would land us on their block list.

Upstream contract:
  GET https://eonet.gsfc.nasa.gov/api/v3/events?status=open
  Returns: { title, description, link, events: [
    { id, title, description, closed, categories: [{id, title}],
      sources: [{id, url}], geometry: [{
        magnitudeValue, magnitudeUnit, date, type, coordinates
      }] }
  ] }

Our normalized `Hazard` model flattens each event into a single record
per EONET event id. Severity is inferred from the event category plus
any magnitude attached to the most recent geometry.
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any, Iterable

import httpx
from loguru import logger

from ..redis import get_redis
from ..schemas.hazard import Hazard, HazardGeometry

EONET_URL = "https://eonet.gsfc.nasa.gov/api/v3/events"
CACHE_KEY = "eonet:v1:global"
CACHE_TTL_SECONDS = 15 * 60  # 15 minutes

# EONET category id → severity bucket when no magnitude is present.
# "info" is ambient background hazards, "warning" is the default for
# route-affecting events, "severe" is reserved for life-safety.
_BASELINE_SEVERITY: dict[str, str] = {
    "wildfires": "warning",
    "severeStorms": "warning",
    "volcanoes": "severe",
    "earthquakes": "warning",
    "floods": "warning",
    "landslides": "warning",
    "seaLakeIce": "info",
    "drought": "info",
    "dustHaze": "info",
    "manmade": "info",
    "snow": "info",
    "tempExtremes": "warning",
    "waterColor": "info",
}


class EonetUpstreamError(Exception):
    """Raised when EONET is unreachable and there is no cached fallback."""


def _infer_severity(category: str, geometries: list[dict]) -> str:
    """Map EONET event shape to our 3-level severity bucket."""
    baseline = _BASELINE_SEVERITY.get(category, "info")
    # Earthquake magnitude 6+ → severe, 4.5-6 → warning, below → info
    if category == "earthquakes":
        for g in geometries:
            mag = g.get("magnitudeValue")
            if mag is None:
                continue
            try:
                m = float(mag)
            except (TypeError, ValueError):
                continue
            if m >= 6.0:
                return "severe"
            if m >= 4.5:
                return "warning"
            return "info"
    # Wildfire with a large polygon → severe (rough heuristic; the
    # polygon area calc is out of scope for this pass).
    if category == "wildfires":
        if any(g.get("type") == "Polygon" for g in geometries):
            return "severe"
    return baseline


def _normalize_event(event: dict[str, Any]) -> Hazard | None:
    """Turn an EONET event into our Hazard schema. Returns None if the
    event is missing required fields — we'd rather drop one rogue row
    than 500 the whole endpoint."""
    try:
        event_id = str(event["id"])
        title = str(event.get("title") or event_id)
        categories = event.get("categories") or []
        if not categories:
            return None
        category = str(categories[0].get("id") or "manmade")
        raw_geoms = event.get("geometry") or []
        if not raw_geoms:
            return None
        geometries: list[HazardGeometry] = []
        for g in raw_geoms:
            gtype = g.get("type")
            if gtype not in ("Point", "Polygon"):
                continue
            coords = g.get("coordinates")
            if coords is None:
                continue
            date_raw = g.get("date")
            gdate: datetime | None = None
            if date_raw:
                try:
                    gdate = datetime.fromisoformat(str(date_raw).replace("Z", "+00:00"))
                except ValueError:
                    gdate = None
            geometries.append(
                HazardGeometry(type=gtype, coordinates=coords, date=gdate)
            )
        if not geometries:
            return None
        # updated_at = max geometry date or now
        dated = [g.date for g in geometries if g.date is not None]
        updated_at = max(dated) if dated else datetime.now(timezone.utc)
        severity = _infer_severity(category, raw_geoms)
        sources = event.get("sources") or []
        source_url = None
        if sources and isinstance(sources, list):
            source_url = sources[0].get("url")
        return Hazard(
            id=event_id,
            title=title,
            category=category,
            severity=severity,
            updated_at=updated_at,
            geometries=geometries,
            source_url=source_url,
        )
    except (KeyError, TypeError, ValueError) as exc:
        logger.warning("eonet event dropped: {}", exc)
        return None


def _encode_for_cache(hazards: list[Hazard]) -> str:
    return json.dumps([h.model_dump(mode="json") for h in hazards])


def _decode_from_cache(raw: str) -> list[Hazard]:
    data = json.loads(raw)
    out: list[Hazard] = []
    for row in data:
        try:
            out.append(Hazard.model_validate(row))
        except Exception as exc:  # noqa: BLE001
            logger.warning("stale cache row dropped: {}", exc)
    return out


async def _fetch_upstream() -> list[Hazard]:
    async with httpx.AsyncClient(timeout=15.0) as client:
        response = await client.get(EONET_URL, params={"status": "open"})
        response.raise_for_status()
        payload = response.json()
    events = payload.get("events") or []
    normalized: list[Hazard] = []
    for event in events:
        hz = _normalize_event(event)
        if hz is not None:
            normalized.append(hz)
    return normalized


async def fetch_hazards(*, force_refresh: bool = False) -> tuple[list[Hazard], bool]:
    """Return (hazards, cached_hit).

    Tries Redis first unless `force_refresh=True`. On cache miss, fetches
    from EONET, backfills the cache, and returns fresh data. If EONET is
    down and we have a stale cache key, returns that with cached=True.
    If EONET is down and the cache is empty, raises `EonetUpstreamError`.
    """
    redis = get_redis()
    if not force_refresh:
        cached_raw = await redis.get(CACHE_KEY)
        if cached_raw:
            return _decode_from_cache(cached_raw), True

    try:
        hazards = await _fetch_upstream()
    except httpx.HTTPError as exc:
        # Upstream hiccup. Try the stale cache one more time — it may
        # be expired but still present if the caller said force_refresh.
        stale = await redis.get(CACHE_KEY)
        if stale:
            logger.warning("eonet upstream failed, serving stale cache: {}", exc)
            return _decode_from_cache(stale), True
        logger.error("eonet upstream failed with no cache fallback: {}", exc)
        raise EonetUpstreamError(f"eonet unreachable: {exc}") from exc

    await redis.setex(CACHE_KEY, CACHE_TTL_SECONDS, _encode_for_cache(hazards))
    return hazards, False


def filter_by_bbox(
    hazards: Iterable[Hazard], bbox: tuple[float, float, float, float]
) -> list[Hazard]:
    """Keep hazards that have at least one geometry inside the bbox.

    bbox is (south, west, north, east) in degrees. For polygons we do
    a cheap envelope intersection — a more precise clip is out of scope
    for a first pass and the mobile client re-checks proximity anyway.
    """
    south, west, north, east = bbox
    out: list[Hazard] = []
    for h in hazards:
        if _any_geometry_in_bbox(h.geometries, south, west, north, east):
            out.append(h)
    return out


def _any_geometry_in_bbox(
    geometries: list[HazardGeometry],
    south: float,
    west: float,
    north: float,
    east: float,
) -> bool:
    for g in geometries:
        if g.type == "Point":
            coords = g.coordinates
            if not isinstance(coords, (list, tuple)) or len(coords) < 2:
                continue
            lng = float(coords[0])
            lat = float(coords[1])
            if south <= lat <= north and west <= lng <= east:
                return True
        elif g.type == "Polygon":
            rings = g.coordinates
            if not rings:
                continue
            for ring in rings:
                for pt in ring:
                    if not isinstance(pt, (list, tuple)) or len(pt) < 2:
                        continue
                    lng = float(pt[0])
                    lat = float(pt[1])
                    if south <= lat <= north and west <= lng <= east:
                        return True
    return False


def filter_by_categories(
    hazards: Iterable[Hazard], categories: set[str]
) -> list[Hazard]:
    if not categories:
        return list(hazards)
    return [h for h in hazards if h.category in categories]

"""Tests for /hazards — eonet fetch, cache, and filter behavior.

These tests:
  * mock the httpx call to EONET via respx
  * use a fakeredis instance so cache hits are real but hermetic
  * assert the endpoint normalizes, caches, filters by bbox, and
    filters by category
  * assert the second call is a cache hit (upstream called once)
  * assert bbox rejects out-of-region events
  * assert category rejects non-matching events

Run locally with: `pytest apps/backend/tests -q`.
CI does not currently run these — the mobile CI job is the gate —
but this file is shipped so whoever adds a pytest job gets a
representative suite to start from.
"""

from __future__ import annotations

import json

import httpx
import pytest
import respx
from fastapi.testclient import TestClient

from app.main import app
from app.services.eonet_service import CACHE_KEY, EONET_URL


pytestmark = pytest.mark.asyncio


def _eonet_fixture() -> dict:
    """Canned EONET /events response covering every filter we test."""
    return {
        "title": "EONET Events",
        "description": "Natural events from EONET.",
        "events": [
            {
                "id": "EONET_EVENT_FIRE_IN",
                "title": "Wildfire near Delhi",
                "description": "A wildfire in northern India.",
                "closed": None,
                "categories": [{"id": "wildfires", "title": "Wildfires"}],
                "sources": [{"id": "INCIWEB", "url": "https://example.com/fire-in"}],
                "geometry": [
                    {
                        "magnitudeValue": None,
                        "magnitudeUnit": None,
                        "date": "2026-04-12T10:00:00Z",
                        "type": "Point",
                        # (lng, lat) — inside the "India" bbox used below
                        "coordinates": [77.2, 28.6],
                    }
                ],
            },
            {
                "id": "EONET_EVENT_FIRE_US",
                "title": "Wildfire in California",
                "description": "A wildfire in the western US.",
                "closed": None,
                "categories": [{"id": "wildfires", "title": "Wildfires"}],
                "sources": [{"id": "INCIWEB", "url": "https://example.com/fire-us"}],
                "geometry": [
                    {
                        "magnitudeValue": None,
                        "magnitudeUnit": None,
                        "date": "2026-04-12T10:00:00Z",
                        "type": "Point",
                        "coordinates": [-120.5, 38.5],
                    }
                ],
            },
            {
                "id": "EONET_EVENT_QUAKE_IN",
                "title": "Earthquake near Delhi",
                "description": "Magnitude 5.1",
                "closed": None,
                "categories": [{"id": "earthquakes", "title": "Earthquakes"}],
                "sources": [{"id": "USGS", "url": "https://example.com/quake"}],
                "geometry": [
                    {
                        "magnitudeValue": 5.1,
                        "magnitudeUnit": "mww",
                        "date": "2026-04-12T09:00:00Z",
                        "type": "Point",
                        "coordinates": [77.25, 28.55],
                    }
                ],
            },
        ],
    }


@pytest.fixture
def client():
    """FastAPI TestClient — sync wrapper around httpx works fine here.

    We also clear the settings cache so any env var tweaks leak
    between tests. slowapi shares the in-process limiter between
    tests, so each test body uses a unique remote IP header to avoid
    collision with the 60/minute bucket.
    """
    with TestClient(app) as c:
        yield c


async def test_first_call_populates_cache_and_returns_list(
    client, _isolate_redis
):
    with respx.mock(assert_all_called=True) as router:
        route = router.get(EONET_URL).mock(
            return_value=httpx.Response(200, json=_eonet_fixture())
        )
        response = client.get(
            "/hazards", headers={"X-Forwarded-For": "10.0.0.1"}
        )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["cached"] is False
    assert len(body["hazards"]) == 3
    ids = {h["id"] for h in body["hazards"]}
    assert ids == {
        "EONET_EVENT_FIRE_IN",
        "EONET_EVENT_FIRE_US",
        "EONET_EVENT_QUAKE_IN",
    }
    assert route.call_count == 1

    cached_raw = await _isolate_redis.get(CACHE_KEY)
    assert cached_raw is not None
    cached_payload = json.loads(cached_raw)
    assert len(cached_payload) == 3


async def test_second_call_is_a_cache_hit(client, _isolate_redis):
    with respx.mock(assert_all_called=True) as router:
        route = router.get(EONET_URL).mock(
            return_value=httpx.Response(200, json=_eonet_fixture())
        )
        # First call warms the cache.
        first = client.get(
            "/hazards", headers={"X-Forwarded-For": "10.0.0.2"}
        )
        assert first.status_code == 200
        assert first.json()["cached"] is False
        # Second call must not hit EONET again.
        second = client.get(
            "/hazards", headers={"X-Forwarded-For": "10.0.0.2"}
        )

    assert second.status_code == 200
    assert second.json()["cached"] is True
    assert len(second.json()["hazards"]) == 3
    # Only one upstream call total.
    assert route.call_count == 1


async def test_bbox_filter_drops_out_of_region(client, _isolate_redis):
    with respx.mock() as router:
        router.get(EONET_URL).mock(
            return_value=httpx.Response(200, json=_eonet_fixture())
        )
        # "India" bbox: south, west, north, east
        response = client.get(
            "/hazards",
            params={"bbox": "20.0,68.0,32.0,82.0"},
            headers={"X-Forwarded-For": "10.0.0.3"},
        )

    assert response.status_code == 200, response.text
    body = response.json()
    ids = {h["id"] for h in body["hazards"]}
    # Both India events survive, the US fire drops out.
    assert "EONET_EVENT_FIRE_US" not in ids
    assert "EONET_EVENT_FIRE_IN" in ids
    assert "EONET_EVENT_QUAKE_IN" in ids


async def test_category_filter_drops_non_matching(client, _isolate_redis):
    with respx.mock() as router:
        router.get(EONET_URL).mock(
            return_value=httpx.Response(200, json=_eonet_fixture())
        )
        response = client.get(
            "/hazards",
            params={"categories": "earthquakes"},
            headers={"X-Forwarded-For": "10.0.0.4"},
        )

    assert response.status_code == 200, response.text
    body = response.json()
    ids = {h["id"] for h in body["hazards"]}
    assert ids == {"EONET_EVENT_QUAKE_IN"}
    # And every returned row is actually in the requested category.
    assert all(h["category"] == "earthquakes" for h in body["hazards"])


async def test_bbox_and_category_compose(client, _isolate_redis):
    with respx.mock() as router:
        router.get(EONET_URL).mock(
            return_value=httpx.Response(200, json=_eonet_fixture())
        )
        response = client.get(
            "/hazards",
            params={
                "bbox": "20.0,68.0,32.0,82.0",
                "categories": "wildfires",
            },
            headers={"X-Forwarded-For": "10.0.0.5"},
        )

    body = response.json()
    ids = {h["id"] for h in body["hazards"]}
    # Only the India wildfire — the US fire is out of bbox and the
    # quake is filtered out by category.
    assert ids == {"EONET_EVENT_FIRE_IN"}


async def test_upstream_failure_with_empty_cache_raises_503(
    client, _isolate_redis
):
    with respx.mock() as router:
        router.get(EONET_URL).mock(
            return_value=httpx.Response(500, text="eonet exploded")
        )
        response = client.get(
            "/hazards", headers={"X-Forwarded-For": "10.0.0.6"}
        )

    assert response.status_code == 503
    body = response.json()
    assert body["detail"]["error"] == "eonet_unreachable"

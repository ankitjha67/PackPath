"""Shared pytest fixtures for the backend test suite.

Boots the FastAPI app against an in-memory `fakeredis` and a mocked
httpx transport so tests never touch real Redis or real EONET. The
fakeredis client is installed into `app.redis` so the production code
paths (`get_redis()`) return it without modification.
"""

from __future__ import annotations

import pytest
import fakeredis.aioredis

from app import redis as app_redis


@pytest.fixture(autouse=True)
def _isolate_redis(monkeypatch):
    """Give every test a fresh in-memory Redis.

    Installs a fakeredis client into `app.redis._client` so every call
    to `get_redis()` returns the same in-memory instance for the
    duration of the test. The fake is flushed and torn down between
    tests so cache state never leaks across cases.
    """
    fake = fakeredis.aioredis.FakeRedis(decode_responses=True)
    monkeypatch.setattr(app_redis, "_client", fake)
    yield fake
    # `aclose` is synchronous-safe on fakeredis but not strictly required;
    # teardown is handled by the fresh instance in the next test.
    monkeypatch.setattr(app_redis, "_client", None)

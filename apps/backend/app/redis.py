"""Redis client + helpers for trip pub/sub fan-out."""

from __future__ import annotations

from typing import AsyncIterator

import redis.asyncio as redis_async

from .config import get_settings

_settings = get_settings()
_client: redis_async.Redis | None = None


def get_redis() -> redis_async.Redis:
    global _client
    if _client is None:
        _client = redis_async.from_url(
            _settings.redis_url, encoding="utf-8", decode_responses=True
        )
    return _client


async def close_redis() -> None:
    global _client
    if _client is not None:
        await _client.aclose()
        _client = None


def trip_channel(trip_id: str) -> str:
    return f"trip:{trip_id}"


async def publish_trip(trip_id: str, payload: str) -> None:
    await get_redis().publish(trip_channel(trip_id), payload)


async def subscribe_trip(trip_id: str) -> AsyncIterator[str]:
    pubsub = get_redis().pubsub()
    await pubsub.subscribe(trip_channel(trip_id))
    try:
        async for message in pubsub.listen():
            if message.get("type") == "message":
                yield message["data"]
    finally:
        await pubsub.unsubscribe(trip_channel(trip_id))
        await pubsub.aclose()

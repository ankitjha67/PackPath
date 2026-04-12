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


def trip_presence_key(trip_id: str) -> str:
    """Redis SET of user_ids currently connected to this trip's WS, across
    every backend pod. Used to skip FCM pushes for users that already see
    the message live."""
    return f"trip:{trip_id}:online"


async def mark_online(trip_id: str, user_id: str) -> None:
    await get_redis().sadd(trip_presence_key(trip_id), user_id)


async def mark_offline(trip_id: str, user_id: str) -> None:
    await get_redis().srem(trip_presence_key(trip_id), user_id)


async def online_user_ids(trip_id: str) -> set[str]:
    members = await get_redis().smembers(trip_presence_key(trip_id))
    return set(members)


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

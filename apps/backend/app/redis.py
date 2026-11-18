"""Redis client + helpers for trip pub/sub fan-out."""

from __future__ import annotations

import time
from typing import AsyncIterator

import redis.asyncio as redis_async

from .config import get_settings

# A presence entry expires this many seconds after its last heartbeat, so a
# pod that dies without cleanup (crash / SIGKILL / deploy) no longer leaves a
# user "online" forever (which would permanently suppress their FCM pushes).
PRESENCE_TTL_SECONDS = 90

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
    """Redis sorted-set of live WS connections for this trip, across every
    backend pod. Members are ``"{user_id}|{connection_id}"`` and the score is
    the entry's expiry epoch, so presence self-heals on crashes and a user with
    multiple devices stays online until *all* their connections drop. Used to
    skip FCM pushes for users already watching the trip live."""
    return f"trip:{trip_id}:online"


def _presence_member(user_id: str, connection_id: str) -> str:
    return f"{user_id}|{connection_id}"


async def mark_online(
    trip_id: str,
    user_id: str,
    connection_id: str,
    ttl: int = PRESENCE_TTL_SECONDS,
) -> None:
    """Register (or heartbeat-refresh) one connection's presence."""
    key = trip_presence_key(trip_id)
    now = time.time()
    r = get_redis()
    await r.zadd(key, {_presence_member(user_id, connection_id): now + ttl})
    # Drop any entries whose heartbeat has lapsed.
    await r.zremrangebyscore(key, "-inf", now)
    # Bound the key's own lifetime so an abandoned trip's set is reclaimed.
    await r.expire(key, ttl * 2)


async def mark_offline(trip_id: str, user_id: str, connection_id: str) -> None:
    await get_redis().zrem(
        trip_presence_key(trip_id), _presence_member(user_id, connection_id)
    )


async def online_user_ids(trip_id: str) -> set[str]:
    """User-ids with at least one non-expired connection."""
    now = time.time()
    members = await get_redis().zrangebyscore(
        trip_presence_key(trip_id), now, "+inf"
    )
    return {m.split("|", 1)[0] for m in members}


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

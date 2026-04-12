"""Rate limiting setup for FastAPI.

`slowapi` is the FastAPI-friendly Flask-Limiter port. We expose a single
process-local `Limiter` instance with a custom key function that prefers
the request body's `phone` field (so we throttle per-phone instead of
per-IP for the OTP endpoints) and falls back to the remote address.

Per-route decorators in `routers/auth.py` apply the actual limits.
"""

from __future__ import annotations

from slowapi import Limiter
from slowapi.util import get_remote_address
from starlette.requests import Request


def _key_for_request(request: Request) -> str:
    """Use the JSON `phone` field if present, else the remote IP."""
    cached: dict | None = getattr(request.state, "_phone_key", None)
    if cached is not None:
        return cached.get("phone") or get_remote_address(request)
    # The middleware runs before the body is parsed, so we can't read it
    # here without consuming the stream. Routes that need per-phone limits
    # populate `request.state._phone_key` themselves before relying on
    # `@limiter.limit(...)`. Until then we fall back to IP — still strictly
    # better than no limit at all.
    return get_remote_address(request)


limiter = Limiter(key_func=_key_for_request)

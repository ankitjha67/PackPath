"""Rate limiting setup for FastAPI.

`slowapi` is the FastAPI-friendly Flask-Limiter port. We expose a single
`Limiter` instance used by the per-route decorators in `routers/auth.py`.

Keying: slowapi evaluates the key function *before* the request body is
parsed, so it cannot see the JSON `phone` field — these decorators therefore
throttle per **IP** (a coarse guard against a single noisy client). True
per-phone throttling (the SMS-bomb guard, which must survive IP rotation and
span workers) is enforced inside the OTP endpoints via a Redis counter — see
`_enforce_phone_request_limit` in `routers/auth.py`, which uses the shared
app Redis client directly.
"""

from __future__ import annotations

from slowapi import Limiter
from slowapi.util import get_remote_address
from starlette.requests import Request

from .config import get_settings


def _client_key(request: Request) -> str:
    """Rate-limit key. Behind a trusted proxy (TRUST_PROXY=true) use the
    left-most X-Forwarded-For hop so each real client gets its own bucket;
    otherwise fall back to the direct peer address."""
    if get_settings().trust_proxy:
        fwd = request.headers.get("x-forwarded-for")
        if fwd:
            return fwd.split(",")[0].strip()
    return get_remote_address(request)


limiter = Limiter(key_func=_client_key)

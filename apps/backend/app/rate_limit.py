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

limiter = Limiter(key_func=get_remote_address)

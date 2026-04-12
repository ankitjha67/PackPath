"""JWT issue/verify and OTP helpers."""

from __future__ import annotations

import secrets
from datetime import datetime, timedelta, timezone
from typing import Any

from jose import JWTError, jwt

from .config import get_settings

_settings = get_settings()


def _now() -> datetime:
    return datetime.now(tz=timezone.utc)


def _encode(payload: dict[str, Any], expires: datetime) -> str:
    to_encode = {**payload, "exp": expires, "iat": _now()}
    return jwt.encode(to_encode, _settings.jwt_secret, algorithm=_settings.jwt_algorithm)


def issue_access_token(user_id: str) -> str:
    expires = _now() + timedelta(minutes=_settings.jwt_access_ttl_minutes)
    return _encode({"sub": user_id, "type": "access"}, expires)


def issue_refresh_token(user_id: str) -> str:
    expires = _now() + timedelta(days=_settings.jwt_refresh_ttl_days)
    return _encode({"sub": user_id, "type": "refresh"}, expires)


def decode_token(token: str) -> dict[str, Any]:
    try:
        return jwt.decode(token, _settings.jwt_secret, algorithms=[_settings.jwt_algorithm])
    except JWTError as exc:
        raise ValueError("invalid token") from exc


def generate_otp() -> str:
    n = _settings.otp_length
    return "".join(str(secrets.randbelow(10)) for _ in range(n))


def generate_join_code() -> str:
    """6-char alphanumeric code, unambiguous (no 0/O/1/I/L)."""
    alphabet = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
    return "".join(secrets.choice(alphabet) for _ in range(6))

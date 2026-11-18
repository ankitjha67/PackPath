"""Phone-OTP auth.

Dev mode (no MSG91 key): the OTP is returned in the API response so you can
test end-to-end without paying for SMS.

Rate limits:
- POST /auth/otp/request: 5/minute, keyed on phone (falls back to IP)
- POST /auth/otp/verify:  10/5minute, plus a Redis-backed cooldown:
  3 failed verifies from the same phone within 5 minutes triggers a
  10-minute lockout.
"""

import secrets
import uuid

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import get_settings
from ..db import get_session
from ..models.user import User
from ..rate_limit import limiter
from ..redis import get_redis
from ..services.identity import new_identity
from ..services.sms import SmsDeliveryError, send_otp_sms
from ..schemas.auth import (
    OtpRequest,
    OtpRequestResponse,
    OtpVerify,
    RefreshRequest,
    TokenPair,
)
from ..security import (
    decode_token,
    generate_otp,
    issue_access_token,
    issue_refresh_token,
)

router = APIRouter(prefix="/auth", tags=["auth"])
_settings = get_settings()


def _otp_key(phone: str) -> str:
    return f"otp:{phone}"


def _verify_fail_key(phone: str) -> str:
    return f"otp:fail:{phone}"


def _verify_cooldown_key(phone: str) -> str:
    return f"otp:cooldown:{phone}"


_FAIL_WINDOW_SECONDS = 300  # 5 minutes
_FAIL_THRESHOLD = 3
_COOLDOWN_SECONDS = 600  # 10 minutes

# Per-phone OTP-request cap. The slowapi decorators throttle per-IP, which an
# attacker rotating IPs sidesteps and which lets one IP request codes for many
# numbers. This Redis counter is keyed on the phone itself and is shared across
# workers/replicas, so it actually bounds SMS sent to any single number.
_REQUEST_LIMIT = 5
_REQUEST_WINDOW_SECONDS = 600  # 10 minutes


def _request_rl_key(phone: str) -> str:
    return f"otp:req:{phone}"


# INCR and the first-hit EXPIRE must be atomic: a crash between two separate
# commands could leave the counter with no TTL, locking a number out forever.
_REQUEST_LIMIT_LUA = """
local c = redis.call('INCR', KEYS[1])
if c == 1 then
  redis.call('EXPIRE', KEYS[1], ARGV[1])
end
return c
"""


async def _enforce_phone_request_limit(redis, phone: str) -> None:
    count = await redis.eval(
        _REQUEST_LIMIT_LUA,
        1,
        _request_rl_key(phone),
        _REQUEST_WINDOW_SECONDS,
    )
    if int(count) > _REQUEST_LIMIT:
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "too many OTP requests for this number; try again later",
        )


@router.post("/otp/request", response_model=OtpRequestResponse)
@limiter.limit("5/minute")
async def request_otp(
    request: Request, payload: OtpRequest
) -> OtpRequestResponse:
    redis = get_redis()
    # Per-phone throttle (Redis, cross-worker) — the real SMS-bomb guard.
    await _enforce_phone_request_limit(redis, payload.phone)
    code = generate_otp()
    await redis.setex(_otp_key(payload.phone), _settings.otp_ttl_seconds, code)
    if _settings.otp_dev_mode:
        return OtpRequestResponse(sent=True, debug_otp=code)
    # Production: deliver the code over SMS via MSG91.
    try:
        await send_otp_sms(payload.phone, code)
    except SmsDeliveryError as exc:
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY,
            "could not send the OTP SMS; please try again",
        ) from exc
    return OtpRequestResponse(sent=True)


@router.post("/otp/verify", response_model=TokenPair)
@limiter.limit("10/5minute")
async def verify_otp(
    request: Request,
    payload: OtpVerify,
    session: AsyncSession = Depends(get_session),
) -> TokenPair:
    redis = get_redis()

    # Progressive backoff: if this phone is currently in cooldown, fail fast.
    if await redis.get(_verify_cooldown_key(payload.phone)):
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "too many attempts; try again in a few minutes",
        )

    expected = await redis.get(_otp_key(payload.phone))
    if not expected or not secrets.compare_digest(expected, payload.code):
        # Track the failure and trip the cooldown if we crossed the threshold.
        fails = await redis.incr(_verify_fail_key(payload.phone))
        if fails == 1:
            await redis.expire(_verify_fail_key(payload.phone), _FAIL_WINDOW_SECONDS)
        if fails >= _FAIL_THRESHOLD:
            await redis.setex(
                _verify_cooldown_key(payload.phone), _COOLDOWN_SECONDS, "1"
            )
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid or expired code")

    await redis.delete(_otp_key(payload.phone))
    await redis.delete(_verify_fail_key(payload.phone))

    user = await session.scalar(select(User).where(User.phone == payload.phone))
    if user is None:
        display_name, avatar_url = new_identity()
        user = User(
            phone=payload.phone,
            display_name=display_name,
            avatar_url=avatar_url,
        )
        session.add(user)
        await session.commit()
        await session.refresh(user)

    return TokenPair(
        access_token=issue_access_token(str(user.id)),
        refresh_token=await _issue_and_store_refresh(redis, str(user.id)),
    )


_REFRESH_TTL_SECONDS = _settings.jwt_refresh_ttl_days * 86400


def _refresh_jti_key(jti: str) -> str:
    return f"refresh:{jti}"


async def _issue_and_store_refresh(redis, user_id: str) -> str:
    """Issue a refresh token and register its jti as the one valid token in
    this chain, so it can be rotated (one-time use) and revoked."""
    token = issue_refresh_token(user_id)
    claims = decode_token(token)
    await redis.setex(
        _refresh_jti_key(claims["jti"]), _REFRESH_TTL_SECONDS, user_id
    )
    return token


@router.post("/refresh", response_model=TokenPair)
async def refresh_token(
    payload: RefreshRequest,
    session: AsyncSession = Depends(get_session),
) -> TokenPair:
    redis = get_redis()
    try:
        claims = decode_token(payload.refresh_token)
    except ValueError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid token") from None
    if claims.get("type") != "refresh":
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "wrong token type")
    sub = claims.get("sub")
    jti = claims.get("jti")
    if not sub or not jti:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "no subject")
    # One-time use with reuse detection: atomically consume the stored jti.
    # A replayed or revoked token won't be present → reject.
    stored = await redis.getdel(_refresh_jti_key(jti))
    if stored is None or stored != sub:
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED, "refresh token revoked or already used"
        )
    # The user may have been deleted since the token was minted.
    try:
        user = await session.get(User, uuid.UUID(sub))
    except (ValueError, TypeError):
        user = None
    if user is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "no such user")
    return TokenPair(
        access_token=issue_access_token(sub),
        refresh_token=await _issue_and_store_refresh(redis, sub),
    )

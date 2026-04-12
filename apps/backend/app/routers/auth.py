"""Phone-OTP auth.

Dev mode (no MSG91 key): the OTP is returned in the API response so you can
test end-to-end without paying for SMS.

Rate limits:
- POST /auth/otp/request: 5/minute, keyed on phone (falls back to IP)
- POST /auth/otp/verify:  10/5minute, plus a Redis-backed cooldown:
  3 failed verifies from the same phone within 5 minutes triggers a
  10-minute lockout.
"""

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import get_settings
from ..db import get_session
from ..models.user import User
from ..rate_limit import limiter
from ..redis import get_redis
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


@router.post("/otp/request", response_model=OtpRequestResponse)
@limiter.limit("5/minute")
async def request_otp(
    request: Request, payload: OtpRequest
) -> OtpRequestResponse:
    # Surface the phone to the limiter key function so per-phone bucketing
    # actually happens (otherwise the middleware falls back to IP).
    request.state._phone_key = {"phone": payload.phone}
    code = generate_otp()
    await get_redis().setex(_otp_key(payload.phone), _settings.otp_ttl_seconds, code)
    if _settings.otp_dev_mode:
        return OtpRequestResponse(sent=True, debug_otp=code)
    # TODO: integrate MSG91 send call here.
    return OtpRequestResponse(sent=True)


@router.post("/otp/verify", response_model=TokenPair)
@limiter.limit("10/5minute")
async def verify_otp(
    request: Request,
    payload: OtpVerify,
    session: AsyncSession = Depends(get_session),
) -> TokenPair:
    request.state._phone_key = {"phone": payload.phone}
    redis = get_redis()

    # Progressive backoff: if this phone is currently in cooldown, fail fast.
    if await redis.get(_verify_cooldown_key(payload.phone)):
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "too many attempts; try again in a few minutes",
        )

    expected = await redis.get(_otp_key(payload.phone))
    if not expected or expected != payload.code:
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
        user = User(phone=payload.phone)
        session.add(user)
        await session.commit()
        await session.refresh(user)

    return TokenPair(
        access_token=issue_access_token(str(user.id)),
        refresh_token=issue_refresh_token(str(user.id)),
    )


@router.post("/refresh", response_model=TokenPair)
async def refresh_token(payload: RefreshRequest) -> TokenPair:
    try:
        claims = decode_token(payload.refresh_token)
    except ValueError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid token") from None
    if claims.get("type") != "refresh":
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "wrong token type")
    sub = claims.get("sub")
    if not sub:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "no subject")
    return TokenPair(
        access_token=issue_access_token(sub),
        refresh_token=issue_refresh_token(sub),
    )

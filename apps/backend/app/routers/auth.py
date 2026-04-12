"""Phone-OTP auth.

Dev mode (no MSG91 key): the OTP is returned in the API response so you can
test end-to-end without paying for SMS.
"""

from __future__ import annotations

import json
import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import get_settings
from ..db import get_session
from ..models.user import User
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


@router.post("/otp/request", response_model=OtpRequestResponse)
async def request_otp(payload: OtpRequest) -> OtpRequestResponse:
    code = generate_otp()
    await get_redis().setex(_otp_key(payload.phone), _settings.otp_ttl_seconds, code)
    if _settings.otp_dev_mode:
        return OtpRequestResponse(sent=True, debug_otp=code)
    # TODO: integrate MSG91 send call here.
    return OtpRequestResponse(sent=True)


@router.post("/otp/verify", response_model=TokenPair)
async def verify_otp(
    payload: OtpVerify, session: AsyncSession = Depends(get_session)
) -> TokenPair:
    redis = get_redis()
    expected = await redis.get(_otp_key(payload.phone))
    if not expected or expected != payload.code:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid or expired code")
    await redis.delete(_otp_key(payload.phone))

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

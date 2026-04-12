"""Shared FastAPI dependencies."""

from __future__ import annotations

import uuid

from fastapi import Depends, Header, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .db import get_session
from .models.trip import TripMember
from .models.user import User
from .security import decode_token


async def current_user(
    authorization: str | None = Header(default=None),
    session: AsyncSession = Depends(get_session),
) -> User:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "missing bearer token")
    token = authorization.split(" ", 1)[1]
    try:
        claims = decode_token(token)
    except ValueError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid token") from None
    if claims.get("type") != "access":
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "wrong token type")
    user_id = claims.get("sub")
    if not user_id:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "no subject")
    user = await session.get(User, uuid.UUID(user_id))
    if user is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "user not found")
    return user


async def require_trip_member(
    trip_id: uuid.UUID,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> TripMember:
    member = await session.scalar(
        select(TripMember).where(
            TripMember.trip_id == trip_id, TripMember.user_id == user.id
        )
    )
    if member is None or member.left_at is not None:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "not a trip member")
    return member


async def require_admin(user: User = Depends(current_user)) -> User:
    """Gates /admin/* routes. Only users with `is_admin=true` can read
    operational and business analytics. Set the flag manually in the DB
    until a real admin-bootstrap flow ships."""
    if not user.is_admin:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "admin access required")
    return user

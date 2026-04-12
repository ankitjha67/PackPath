"""LiveKit token mint for the per-trip push-to-talk room.

Each trip gets one LiveKit room named `trip-{trip_id}`. The mobile client
calls this endpoint when the user joins the voice channel and uses the
returned access token + LIVEKIT_URL to connect via the LiveKit SDK.

We mint the token in-process rather than pulling in `livekit-server-sdk`
because it's just a small JWT with a specific `video` grant. This keeps
the dependency footprint tiny and lets us self-host LiveKit later
without changing this code.
"""

from __future__ import annotations

import re
import time
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from jose import jwt
from pydantic import BaseModel

from ..config import get_settings
from ..deps import current_user, require_trip_member
from ..models.trip import TripMember
from ..models.user import User

router = APIRouter(prefix="/trips/{trip_id}/voice", tags=["voice"])

# Built-in channel slugs (same set as the mobile picker).
_BUILTIN_CHANNELS = {"everyone", "drivers"}
# Free-form channels (e.g. sub-group ids) must be safe for a LiveKit room name.
_CHANNEL_RE = re.compile(r"^[a-zA-Z0-9_-]{1,40}$")


class VoiceTokenResponse(BaseModel):
    url: str
    token: str
    room: str
    identity: str
    channel: str


@router.post("/token", response_model=VoiceTokenResponse)
async def mint_voice_token(
    trip_id: uuid.UUID,
    channel: str = Query(default="everyone"),
    user: User = Depends(current_user),
    _: TripMember = Depends(require_trip_member),
) -> VoiceTokenResponse:
    settings = get_settings()
    if not (
        settings.livekit_url
        and settings.livekit_api_key
        and settings.livekit_api_secret
    ):
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "LiveKit is not configured",
        )
    if channel not in _BUILTIN_CHANNELS and not _CHANNEL_RE.match(channel):
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "channel must be 'everyone', 'drivers', or a slug",
        )

    room = f"trip-{trip_id}-{channel}"
    identity = str(user.id)
    now = int(time.time())
    claims = {
        "iss": settings.livekit_api_key,
        "sub": identity,
        "iat": now,
        "exp": now + 6 * 3600,  # 6h token; mobile can re-mint as needed
        "name": user.display_name or user.phone,
        "video": {
            "room": room,
            "roomJoin": True,
            "canPublish": True,
            "canSubscribe": True,
            "canPublishData": True,
        },
    }
    token = jwt.encode(claims, settings.livekit_api_secret, algorithm="HS256")
    return VoiceTokenResponse(
        url=settings.livekit_url,
        token=token,
        room=room,
        identity=identity,
        channel=channel,
    )

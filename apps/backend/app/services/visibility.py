"""Central location-visibility policy.

A member's live location may be withheld from a given viewer for three reasons,
all of which were previously persisted but never enforced on read paths:

* ``ghost_mode`` — the member is hidden from everyone but themselves.
* ``share_until`` — sharing has a deadline; past it, the member is hidden.
* ``visibility_scope`` — JSONB of ``{"type": "all" | "none" | "some", ...}``.
  ``some`` carries a ``members`` allowlist of user-ids that may see them.

Every path that surfaces another member's coordinates (ETAs, live-link,
WebSocket fan-out) resolves the visible set through here so the rules stay in
one place.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..models.trip import TripMember


def _member_visible_to(
    member: TripMember,
    viewer_id: uuid.UUID | None,
    now: datetime,
) -> bool:
    # You always see yourself.
    if viewer_id is not None and member.user_id == viewer_id:
        return True
    if member.ghost_mode:
        return False
    if member.share_until is not None and member.share_until <= now:
        return False
    scope = member.visibility_scope or {"type": "all"}
    stype = scope.get("type", "all")
    if stype == "all":
        return True
    if stype == "some":
        allowed = {str(m) for m in scope.get("members", [])}
        # A public (unauthenticated) viewer is not in any allowlist.
        return viewer_id is not None and str(viewer_id) in allowed
    # "none" (or anything unrecognised) → hidden.
    return False


async def visible_member_ids(
    session: AsyncSession,
    trip_id: uuid.UUID,
    viewer_id: uuid.UUID | None,
) -> set[uuid.UUID]:
    """User-ids of active members whose location ``viewer_id`` may see.

    Pass ``viewer_id=None`` for a public viewer (e.g. a live-link), which gets
    no self-exemption and never satisfies a ``some`` allowlist.
    """
    now = datetime.now(timezone.utc)
    members = (
        await session.execute(
            select(TripMember).where(
                TripMember.trip_id == trip_id,
                TripMember.left_at.is_(None),
            )
        )
    ).scalars().all()
    return {
        m.user_id for m in members if _member_visible_to(m, viewer_id, now)
    }

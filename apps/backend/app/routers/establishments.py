from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from geoalchemy2 import Geography, Geometry
from sqlalchemy import cast, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import current_user
from ..models.establishment import (
    ESTABLISHMENT_CATEGORIES,
    Establishment,
    EstablishmentRating,
)
from ..models.user import User
from ..schemas.establishment import (
    EstablishmentCreate,
    EstablishmentOut,
    RatingCreate,
    RatingOut,
)

router = APIRouter(prefix="/establishments", tags=["establishments"])

_LAT = func.ST_Y(cast(Establishment.geom, Geometry))
_LNG = func.ST_X(cast(Establishment.geom, Geometry))


def _point(lat: float, lng: float):
    return cast(func.ST_SetSRID(func.ST_MakePoint(lng, lat), 4326), Geography)


async def _out(
    row,
    *,
    distance_m: float | None = None,
    my_stars: int | None = None,
) -> EstablishmentOut:
    est, lat, lng, avg_stars, rating_count = row
    return EstablishmentOut(
        id=est.id,
        name=est.name,
        category=est.category,
        lat=lat,
        lng=lng,
        address=est.address,
        phone=est.phone,
        notes=est.notes,
        avg_stars=round(float(avg_stars or 0), 2),
        rating_count=int(rating_count or 0),
        distance_m=round(distance_m, 1) if distance_m is not None else None,
        my_stars=my_stars,
        created_at=est.created_at,
    )


def _agg_select():
    """Establishment joined to its rating aggregate, with lat/lng."""
    return (
        select(
            Establishment,
            _LAT.label("lat"),
            _LNG.label("lng"),
            func.coalesce(func.avg(EstablishmentRating.stars), 0).label("avg_stars"),
            func.count(EstablishmentRating.id).label("rating_count"),
        )
        .outerjoin(
            EstablishmentRating,
            EstablishmentRating.establishment_id == Establishment.id,
        )
        .group_by(Establishment.id)
    )


@router.post("", response_model=EstablishmentOut, status_code=status.HTTP_201_CREATED)
async def create_establishment(
    payload: EstablishmentCreate,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> EstablishmentOut:
    if payload.category not in ESTABLISHMENT_CATEGORIES:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "invalid category")
    est = Establishment(
        name=payload.name.strip(),
        category=payload.category,
        geom=func.ST_SetSRID(func.ST_MakePoint(payload.lng, payload.lat), 4326),
        address=payload.address,
        phone=payload.phone,
        notes=payload.notes,
        created_by=user.id,
    )
    session.add(est)
    await session.commit()
    row = (
        await session.execute(_agg_select().where(Establishment.id == est.id))
    ).first()
    return await _out(row)


@router.get("", response_model=list[EstablishmentOut])
async def list_establishments(
    lat: float | None = Query(default=None, ge=-90, le=90),
    lng: float | None = Query(default=None, ge=-180, le=180),
    radius_km: float = Query(default=25, gt=0, le=500),
    category: str | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=300),
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> list[EstablishmentOut]:
    """Nearby places (or all, if no point given), each with its rating
    aggregate, nearest first when a point is supplied."""
    stmt = _agg_select()
    if category:
        stmt = stmt.where(Establishment.category == category)

    distance_label = None
    if lat is not None and lng is not None:
        point = _point(lat, lng)
        distance_label = func.ST_Distance(Establishment.geom, point).label("distance_m")
        stmt = (
            stmt.add_columns(distance_label)
            .where(func.ST_DWithin(Establishment.geom, point, radius_km * 1000))
            .order_by(distance_label.asc())
        )
    else:
        stmt = stmt.order_by(Establishment.created_at.desc())
    stmt = stmt.limit(limit)

    # Which of these has the current user already rated?
    rows = (await session.execute(stmt)).all()
    ids = [r[0].id for r in rows]
    mine = await _my_stars_for(session, user.id, ids)
    out = []
    for r in rows:
        dist = r[-1] if distance_label is not None else None
        out.append(await _out(r[:5], distance_m=dist, my_stars=mine.get(r[0].id)))
    return out


@router.get("/{establishment_id}", response_model=EstablishmentOut)
async def get_establishment(
    establishment_id: uuid.UUID,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> EstablishmentOut:
    row = (
        await session.execute(
            _agg_select().where(Establishment.id == establishment_id)
        )
    ).first()
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "establishment not found")
    mine = await _my_stars_for(session, user.id, [establishment_id])
    return await _out(row, my_stars=mine.get(establishment_id))


@router.get("/{establishment_id}/ratings", response_model=list[RatingOut])
async def list_ratings(
    establishment_id: uuid.UUID,
    limit: int = Query(default=50, ge=1, le=200),
    _: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> list[RatingOut]:
    rows = (
        await session.execute(
            select(EstablishmentRating, User)
            .outerjoin(User, User.id == EstablishmentRating.user_id)
            .where(EstablishmentRating.establishment_id == establishment_id)
            .order_by(EstablishmentRating.updated_at.desc())
            .limit(limit)
        )
    ).all()
    return [
        RatingOut(
            id=r.id,
            user_id=r.user_id,
            reviewer_name=u.display_name if u else None,
            reviewer_avatar=u.avatar_url if u else None,
            stars=r.stars,
            comment=r.comment,
            tags=r.tags,
            created_at=r.created_at,
        )
        for r, u in rows
    ]


@router.post(
    "/{establishment_id}/ratings",
    response_model=EstablishmentOut,
    status_code=status.HTTP_201_CREATED,
)
async def rate_establishment(
    establishment_id: uuid.UUID,
    payload: RatingCreate,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> EstablishmentOut:
    """Upsert the current user's rating, then return the place with its fresh
    aggregate so the caller can update in place."""
    est = await session.get(Establishment, establishment_id)
    if est is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "establishment not found")
    existing = await session.scalar(
        select(EstablishmentRating).where(
            EstablishmentRating.establishment_id == establishment_id,
            EstablishmentRating.user_id == user.id,
        )
    )
    if existing is None:
        session.add(
            EstablishmentRating(
                establishment_id=establishment_id,
                user_id=user.id,
                stars=payload.stars,
                comment=payload.comment,
                tags=payload.tags,
            )
        )
    else:
        existing.stars = payload.stars
        existing.comment = payload.comment
        existing.tags = payload.tags
        existing.updated_at = func.now()
    await session.commit()
    row = (
        await session.execute(
            _agg_select().where(Establishment.id == establishment_id)
        )
    ).first()
    return await _out(row, my_stars=payload.stars)


async def _my_stars_for(
    session: AsyncSession, user_id: uuid.UUID, ids: list[uuid.UUID]
) -> dict[uuid.UUID, int]:
    if not ids:
        return {}
    rows = (
        await session.execute(
            select(EstablishmentRating.establishment_id, EstablishmentRating.stars).where(
                EstablishmentRating.user_id == user_id,
                EstablishmentRating.establishment_id.in_(ids),
            )
        )
    ).all()
    return {eid: stars for eid, stars in rows}

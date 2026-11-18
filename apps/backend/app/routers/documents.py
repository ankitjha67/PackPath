from __future__ import annotations

import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Response, status
from pydantic import BaseModel, ConfigDict, Field, model_validator
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import current_user, require_trip_member
from ..models.document import TripDocument
from ..models.trip import TripMember
from ..models.user import User

router = APIRouter(prefix="/trips/{trip_id}/documents", tags=["documents"])


class DocumentCreate(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    kind: str = Field(pattern="^(link|note)$")
    url: str | None = Field(default=None, max_length=1000)
    body: str | None = None

    @model_validator(mode="after")
    def _check(self) -> "DocumentCreate":
        if self.kind == "link" and not self.url:
            raise ValueError("a link document needs a url")
        if self.kind == "note" and not self.body:
            raise ValueError("a note document needs body text")
        return self


class DocumentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    trip_id: uuid.UUID
    added_by: uuid.UUID | None
    title: str
    kind: str
    url: str | None
    body: str | None
    created_at: datetime


@router.get("", response_model=list[DocumentOut])
async def list_documents(
    trip_id: uuid.UUID,
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> list[DocumentOut]:
    rows = (
        await session.scalars(
            select(TripDocument)
            .where(TripDocument.trip_id == trip_id)
            .order_by(TripDocument.created_at.desc())
        )
    ).all()
    return [DocumentOut.model_validate(r) for r in rows]


@router.post("", response_model=DocumentOut, status_code=status.HTTP_201_CREATED)
async def add_document(
    trip_id: uuid.UUID,
    payload: DocumentCreate,
    user: User = Depends(current_user),
    _: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> DocumentOut:
    row = TripDocument(
        trip_id=trip_id,
        added_by=user.id,
        title=payload.title,
        kind=payload.kind,
        url=payload.url,
        body=payload.body,
    )
    session.add(row)
    await session.commit()
    await session.refresh(row)
    return DocumentOut.model_validate(row)


@router.delete(
    "/{document_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
    response_model=None,
)
async def delete_document(
    trip_id: uuid.UUID,
    document_id: uuid.UUID,
    member: TripMember = Depends(require_trip_member),
    session: AsyncSession = Depends(get_session),
) -> None:
    row = await session.get(TripDocument, document_id)
    if row is None or row.trip_id != trip_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "not found")
    # The uploader or a marshall can remove a document.
    if row.added_by != member.user_id and member.role not in ("owner", "comarshall"):
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, "only the uploader or marshall can delete"
        )
    await session.delete(row)
    await session.commit()

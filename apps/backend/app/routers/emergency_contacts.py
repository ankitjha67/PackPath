from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, Response, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import current_user
from ..models.emergency_contact import EmergencyContact
from ..models.user import User

router = APIRouter(prefix="/me/emergency-contacts", tags=["emergency-contacts"])


class EmergencyContactCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    phone: str = Field(min_length=3, max_length=30)


class EmergencyContactOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    name: str
    phone: str


@router.get("", response_model=list[EmergencyContactOut])
async def list_contacts(
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> list[EmergencyContactOut]:
    rows = (
        await session.scalars(
            select(EmergencyContact)
            .where(EmergencyContact.user_id == user.id)
            .order_by(EmergencyContact.created_at.asc())
        )
    ).all()
    return [EmergencyContactOut.model_validate(r) for r in rows]


@router.post("", response_model=EmergencyContactOut, status_code=status.HTTP_201_CREATED)
async def add_contact(
    payload: EmergencyContactCreate,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> EmergencyContactOut:
    contact = EmergencyContact(
        user_id=user.id, name=payload.name.strip(), phone=payload.phone.strip()
    )
    session.add(contact)
    await session.commit()
    await session.refresh(contact)
    return EmergencyContactOut.model_validate(contact)


@router.delete(
    "/{contact_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
    response_model=None,
)
async def delete_contact(
    contact_id: uuid.UUID,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> None:
    contact = await session.get(EmergencyContact, contact_id)
    if contact is None or contact.user_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "contact not found")
    await session.delete(contact)
    await session.commit()

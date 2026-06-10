"""Tests for the owner-only trip admin endpoints added in Session 4:

  PATCH  /trips/{id}                      — rename / window update
  DELETE /trips/{id}/members/{user_id}    — kick member (soft delete)

These endpoints are pure authorization + mutation logic over the DB
session, so we test them with FastAPI dependency overrides instead of
a live Postgres: `get_session` yields a recording fake and
`current_user` returns a canned user. The fake implements the four
session calls the handlers make (get / scalar / scalars / commit /
refresh).
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app.db import get_session
from app.deps import current_user
from app.main import app

OWNER_ID = uuid.uuid4()
MEMBER_ID = uuid.uuid4()
TRIP_ID = uuid.uuid4()


def _trip():
    return SimpleNamespace(
        id=TRIP_ID,
        owner_id=OWNER_ID,
        name="Old name",
        status="planned",
        start_at=None,
        end_at=None,
        join_code="ABC123",
        created_at=datetime.now(tz=timezone.utc),
    )


def _member(user_id, role="member"):
    return SimpleNamespace(
        trip_id=TRIP_ID,
        user_id=user_id,
        role=role,
        color="#3B82F6",
        ghost_mode=False,
        joined_at=datetime.now(tz=timezone.utc),
        left_at=None,
    )


class _ScalarsResult:
    def __init__(self, rows):
        self._rows = rows

    def all(self):
        return self._rows


class FakeSession:
    """Implements exactly the AsyncSession surface the trip handlers use."""

    def __init__(self, trip=None, member=None, members=None):
        self.trip = trip
        self.member = member
        self.members = members or []
        self.committed = False

    async def get(self, _model, _pk):
        return self.trip

    async def scalar(self, _stmt):
        return self.member

    async def scalars(self, _stmt):
        return _ScalarsResult(self.members)

    async def commit(self):
        self.committed = True

    async def refresh(self, _obj):
        return None


def _user(user_id):
    return SimpleNamespace(
        id=user_id,
        phone="+910000000000",
        display_name=None,
        avatar_url=None,
        is_admin=False,
        created_at=datetime.now(tz=timezone.utc),
    )


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


def _wire(session, user):
    async def _session_override():
        yield session

    app.dependency_overrides[get_session] = _session_override
    app.dependency_overrides[current_user] = lambda: user


def test_patch_trip_by_non_owner_is_403(client):
    session = FakeSession(trip=_trip())
    _wire(session, _user(MEMBER_ID))
    response = client.patch(f"/trips/{TRIP_ID}", json={"name": "New name"})
    assert response.status_code == 403
    assert not session.committed


def test_patch_trip_rename_by_owner(client):
    trip = _trip()
    session = FakeSession(trip=trip, members=[_member(OWNER_ID, role="owner")])
    _wire(session, _user(OWNER_ID))
    response = client.patch(f"/trips/{TRIP_ID}", json={"name": "New name"})
    assert response.status_code == 200, response.text
    assert trip.name == "New name"
    assert session.committed
    assert response.json()["name"] == "New name"


def test_patch_trip_missing_is_404(client):
    session = FakeSession(trip=None)
    _wire(session, _user(OWNER_ID))
    response = client.patch(f"/trips/{TRIP_ID}", json={"name": "x"})
    assert response.status_code == 404


def test_kick_by_non_owner_is_403(client):
    session = FakeSession(trip=_trip(), member=_member(MEMBER_ID))
    _wire(session, _user(MEMBER_ID))
    response = client.delete(f"/trips/{TRIP_ID}/members/{MEMBER_ID}")
    assert response.status_code == 403
    assert not session.committed


def test_owner_cannot_kick_self(client):
    session = FakeSession(trip=_trip())
    _wire(session, _user(OWNER_ID))
    response = client.delete(f"/trips/{TRIP_ID}/members/{OWNER_ID}")
    assert response.status_code == 400


def test_kick_member_stamps_left_at(client):
    member = _member(MEMBER_ID)
    session = FakeSession(trip=_trip(), member=member)
    _wire(session, _user(OWNER_ID))
    response = client.delete(f"/trips/{TRIP_ID}/members/{MEMBER_ID}")
    assert response.status_code == 204, response.text
    assert member.left_at is not None
    assert session.committed


def test_kick_unknown_member_is_404(client):
    session = FakeSession(trip=_trip(), member=None)
    _wire(session, _user(OWNER_ID))
    response = client.delete(f"/trips/{TRIP_ID}/members/{MEMBER_ID}")
    assert response.status_code == 404

"""Regression tests for the production fail-closed preflight.

These lock in that a non-local deployment refuses to boot with insecure
defaults (a stated guarantee in infra/.env.example and the self-host guide).
"""

from __future__ import annotations

from types import SimpleNamespace

import pytest

import pytest as _pytest
from fastapi import HTTPException

from app.main import _enforce_production_safety
from app.routers.messages import _ensure_not_muted


def _settings(**overrides):
    base = dict(
        environment="production",
        jwt_secret="a-real-and-sufficiently-long-secret-value",
        otp_dev_mode=False,
        cors_origins=["https://app.example.com"],
    )
    base.update(overrides)
    return SimpleNamespace(**base)


def test_production_refuses_default_jwt_secret():
    with pytest.raises(RuntimeError):
        _enforce_production_safety(_settings(jwt_secret="change-me-in-prod"))
    with pytest.raises(RuntimeError):
        _enforce_production_safety(_settings(jwt_secret=""))


def test_production_refuses_dev_otp_mode():
    with pytest.raises(RuntimeError):
        _enforce_production_safety(_settings(otp_dev_mode=True))


def test_production_refuses_wildcard_cors():
    with pytest.raises(RuntimeError):
        _enforce_production_safety(_settings(cors_origins=["*"]))


def test_production_boots_with_safe_config():
    # Should not raise.
    _enforce_production_safety(_settings())


def test_muted_member_cannot_broadcast():
    muted = SimpleNamespace(muted=True)
    with _pytest.raises(HTTPException) as exc:
        _ensure_not_muted(muted)
    assert exc.value.status_code == 403


def test_unmuted_member_may_broadcast():
    # Should not raise.
    _ensure_not_muted(SimpleNamespace(muted=False))


def test_local_skips_all_checks():
    # Local dev is allowed every insecure default.
    _enforce_production_safety(
        _settings(
            environment="local",
            jwt_secret="change-me-in-prod",
            otp_dev_mode=True,
            cors_origins=["*"],
        )
    )

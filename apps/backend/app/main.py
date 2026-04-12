"""FastAPI application factory."""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from loguru import logger
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

from .config import get_settings
from .logging import configure_logging
from .rate_limit import limiter
from .redis import close_redis, get_redis
from .routers import (
    admin_analytics,
    admin_business,
    auth,
    billing,
    devices,
    directions,
    events,
    expenses,
    etas,
    group,
    health,
    livelink,
    maps,
    me,
    messages,
    privacy,
    recap,
    reminders,
    safety,
    trips,
    user_stats,
    voice,
    waypoints,
)
from .ws import trips as trips_ws


_DEFAULT_JWT_SECRETS = {"", "change-me-in-prod"}


def _enforce_production_safety(settings) -> None:
    """Refuse to boot in non-local environments with insecure defaults."""
    if settings.environment == "local":
        return
    if settings.jwt_secret in _DEFAULT_JWT_SECRETS:
        raise RuntimeError(
            "JWT_SECRET must be set to a real value in non-local environments. "
            f"Current environment: {settings.environment}"
        )
    if settings.otp_dev_mode:
        raise RuntimeError(
            "OTP dev mode is on (MSG91_AUTH_KEY is empty) — this would leak "
            "OTPs in API responses. Set MSG91_AUTH_KEY in production."
        )
    if settings.cors_origins == ["*"]:
        raise RuntimeError(
            "CORS_ORIGINS must be an explicit allowlist in non-local "
            "environments, not the default '*'."
        )


@asynccontextmanager
async def lifespan(_: FastAPI):
    settings = get_settings()
    configure_logging(debug=settings.debug)
    _enforce_production_safety(settings)
    if settings.environment == "local" and settings.jwt_secret in _DEFAULT_JWT_SECRETS:
        logger.warning(
            "Running with default JWT_SECRET — fine for local dev, NEVER ship this."
        )
    # Eagerly create the Redis connection so the first request is fast.
    get_redis()
    try:
        yield
    finally:
        await close_redis()


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title="PackPath API",
        version="0.1.0",
        description="Group trip navigation backend.",
        lifespan=lifespan,
    )
    app.state.limiter = limiter
    app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
    app.add_middleware(SlowAPIMiddleware)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins or ["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(health.router)
    app.include_router(auth.router)
    app.include_router(me.router)
    app.include_router(trips.router)
    app.include_router(waypoints.router)
    app.include_router(messages.router)
    app.include_router(directions.router)
    app.include_router(etas.router)
    app.include_router(maps.router)
    app.include_router(devices.router)
    app.include_router(voice.router)
    # v1.1 advanced features
    app.include_router(safety.router)
    app.include_router(livelink.router)
    app.include_router(group.router)
    app.include_router(expenses.router)
    app.include_router(privacy.router)
    app.include_router(recap.router)
    app.include_router(reminders.router)
    app.include_router(events.router)
    app.include_router(user_stats.router)
    app.include_router(billing.router)
    app.include_router(admin_analytics.router)
    app.include_router(admin_business.router)
    app.include_router(trips_ws.router)
    return app


app = create_app()

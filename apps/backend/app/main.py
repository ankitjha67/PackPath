"""FastAPI application factory."""

import asyncio
import contextlib
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
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
    achievements,
    admin_analytics,
    admin_business,
    auth,
    billing,
    checklist,
    contacts,
    devices,
    directions,
    documents,
    emergency_contacts,
    entitlements,
    establishments,
    events,
    expenses,
    etas,
    group,
    hazards,
    health,
    livelink,
    maps,
    me,
    messages,
    navigation,
    notifications,
    preferences,
    privacy,
    recap,
    reminders,
    safety,
    scheduled,
    trips,
    user_stats,
    voice,
    waypoints,
)
from .services.scheduled_sender import run_scheduled_sender
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
    # Background task: fire due scheduled announcements.
    sender_task = asyncio.create_task(run_scheduled_sender())
    try:
        yield
    finally:
        sender_task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await sender_task
        await close_redis()


def create_app() -> FastAPI:
    settings = get_settings()
    # Only expose interactive docs / OpenAPI schema in local dev — outside of
    # it they'd advertise the whole attack surface of a self-hosted instance.
    _docs_enabled = settings.environment == "local"
    app = FastAPI(
        title="PackPath API",
        version="0.1.0",
        description="Group trip navigation backend.",
        lifespan=lifespan,
        docs_url="/docs" if _docs_enabled else None,
        redoc_url="/redoc" if _docs_enabled else None,
        openapi_url="/openapi.json" if _docs_enabled else None,
    )
    app.state.limiter = limiter
    app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
    app.add_middleware(SlowAPIMiddleware)

    # Baseline security headers on every response; force downloads (not inline
    # rendering) for user-uploaded media so a crafted file can't execute as
    # active content on the API origin.
    @app.middleware("http")
    async def _security_headers(request: Request, call_next):
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers.setdefault("Referrer-Policy", "no-referrer")
        if request.url.path.startswith("/media/"):
            response.headers["Content-Disposition"] = "attachment"
        return response
    # Never pair wildcard origins with credentials. With an empty allowlist no
    # cross-origin browser request is permitted; configure CORS_ORIGINS to an
    # explicit list to enable one.
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
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
    app.include_router(scheduled.router)
    app.include_router(documents.router)
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
    app.include_router(contacts.router)
    app.include_router(emergency_contacts.router)
    app.include_router(establishments.router)
    app.include_router(navigation.router)
    app.include_router(checklist.router)
    app.include_router(achievements.router)
    app.include_router(preferences.router)
    app.include_router(notifications.router)
    app.include_router(entitlements.router)
    app.include_router(privacy.router)
    app.include_router(recap.router)
    app.include_router(reminders.router)
    app.include_router(events.router)
    app.include_router(hazards.router)
    app.include_router(user_stats.router)
    app.include_router(billing.router)
    app.include_router(admin_analytics.router)
    app.include_router(admin_business.router)
    app.include_router(trips_ws.router)

    # Serve uploaded chat attachments from local disk (dev). In production
    # these would live in object storage behind a CDN.
    from pathlib import Path as _Path

    from fastapi.staticfiles import StaticFiles

    media_dir = _Path(get_settings().media_dir)
    media_dir.mkdir(parents=True, exist_ok=True)
    app.mount("/media", StaticFiles(directory=str(media_dir)), name="media")
    return app


app = create_app()

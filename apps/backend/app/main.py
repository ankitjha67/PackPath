"""FastAPI application factory."""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import get_settings
from .logging import configure_logging
from .redis import close_redis, get_redis
from .routers import (
    auth,
    devices,
    directions,
    etas,
    health,
    me,
    messages,
    trips,
    voice,
    waypoints,
)
from .ws import trips as trips_ws


@asynccontextmanager
async def lifespan(_: FastAPI):
    settings = get_settings()
    configure_logging(debug=settings.debug)
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
    app.include_router(devices.router)
    app.include_router(voice.router)
    app.include_router(trips_ws.router)
    return app


app = create_app()

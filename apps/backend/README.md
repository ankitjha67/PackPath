# PackPath Backend

FastAPI 0.115 on Python 3.11. Async SQLAlchemy 2 against Postgres 16 with PostGIS + TimescaleDB extensions, Redis for pub/sub fan-out and short-lived cache, `slowapi` for rate limiting, JWT (15 min access + 30 day rotating refresh) for auth.

## App layout

```
app/
├── main.py              FastAPI app factory + router wiring + lifespan
├── config.py            Pydantic settings (env-driven, prod-safety guard)
├── logging.py           loguru structured logging
├── db.py                async SQLAlchemy session + engine
├── redis.py             Redis client + trip channel helpers + presence set
├── rate_limit.py        slowapi Limiter (phone-keyed for OTP, else IP)
├── security.py          JWT mint + decode
├── deps.py              current_user, require_trip_member, require_admin
├── models/              SQLAlchemy models (trips, users, waypoints,
│                        messages, expenses, safety, devices, audit, …)
├── schemas/             Pydantic request/response models
│   └── hazard.py        Hazard + HazardGeometry + HazardsResponse
├── routers/             REST + WebSocket endpoints (one per concern)
├── services/            external integrations + business logic
│   ├── eonet_service.py NASA EONET fetch + Redis cache + bbox/category
│   ├── maps/            pluggable directions providers (6 options)
│   ├── push.py          FCM send, presence-aware
│   └── …                cost, elevation, weather, recap, safety, ingest
└── ws/
    └── trips.py         /ws/trips/{trip_id} — Redis-backed fan-out

alembic/
├── env.py
└── versions/
    ├── 0001_initial.py              core schema + TimescaleDB hypertable
    ├── 0002_advanced_features.py    v1.1 bundle (safety, expenses, …)
    ├── 0003_admin_role.py           `is_admin` column + guard
    └── …                            subsequent migrations land here

tests/
├── __init__.py
├── conftest.py          fakeredis isolation per test
└── test_hazards.py      respx-mocked EONET, cache, bbox, category, 503
```

## Local run

```bash
# 1. Start dependencies (Postgres + PostGIS + TimescaleDB + Redis)
cd ../../infra && docker compose up -d && cd -

# 2. Configure env
cp .env.example .env                    # tweak DATABASE_URL, REDIS_URL, JWT_SECRET

# 3. Install deps
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# 4. Migrate
alembic upgrade head

# 5. Run
uvicorn app.main:app --reload --port 8000
```

- OpenAPI UI: <http://localhost:8000/docs>
- Redoc:      <http://localhost:8000/redoc>
- Health:     <http://localhost:8000/healthz>

## Required environment

| Var                         | What                                                                |
| --------------------------- | ------------------------------------------------------------------- |
| `DATABASE_URL`              | `postgresql+asyncpg://packpath:packpath@localhost:5432/packpath`    |
| `REDIS_URL`                 | `redis://localhost:6379/0`                                          |
| `JWT_SECRET`                | Any random string for local; required non-default in non-local     |
| `MAPBOX_SERVER_TOKEN`       | Optional for local dev; needed for the directions proxy to work    |
| `MAPS_PROVIDER`             | Default provider id (`mapbox`/`google`/`mappls`/`here`/`tomtom`/`osrm`) |
| `MAPS_FALLBACK_PROVIDERS`   | CSV of providers tried in order if the default fails               |
| `LIVEKIT_URL`               | e.g. `wss://…livekit.cloud`                                         |
| `LIVEKIT_API_KEY`           | For PTT voice                                                       |
| `LIVEKIT_API_SECRET`        | For PTT voice                                                       |
| `MSG91_AUTH_KEY`            | Optional; when empty, OTPs are returned in the response (dev only)  |
| `FCM_SERVICE_ACCOUNT_JSON`  | Inline JSON blob for FCM push; optional                             |

A production-safety guard in `app/main.py` refuses to boot when `environment != "local"` unless `JWT_SECRET` is non-default, `MSG91_AUTH_KEY` is set (otherwise OTPs would leak in response bodies), and `CORS_ORIGINS` is explicit (not `*`).

## Routers

| Router                  | Base path                  | One-line                                                             |
| ----------------------- | -------------------------- | -------------------------------------------------------------------- |
| `health`                | `/healthz`                 | Liveness + readiness                                                 |
| `auth`                  | `/auth`                    | OTP request/verify, JWT refresh, rotating refresh flow               |
| `me`                    | `/me`                      | Profile read/update + personal stats                                 |
| `trips`                 | `/trips`                   | CRUD, join-by-code, leave, end, ghost mode                           |
| `waypoints`             | `/trips/{id}/waypoints`    | Waypoint CRUD + reorder                                              |
| `messages`              | `/trips/{id}/messages`     | Chat history (REST); WS preferred for sending                        |
| `directions`            | `/trips/{id}/directions`   | Directions proxy + optional cost/weather/elevation enrichments       |
| `etas`                  | `/trips/{id}/etas`         | Per-member ETA to next waypoint                                      |
| `maps`                  | `/maps`                    | `/maps/providers` — which providers the server has keys for         |
| `devices`               | `/devices`                 | FCM device registration                                              |
| `voice`                 | `/trips/{id}/voice`        | LiveKit token mint, per-channel room routing                         |
| `safety`                | `/trips/{id}/safety`       | SOS, crash, stranded; drives WS `safety` fan-out                     |
| `livelink`              | `/trips/{id}/livelink`     | Mint read-only JWT + serve stripped public snapshot                  |
| `group`                 | `/trips/{id}/groups`       | Sub-groups + ready-check                                             |
| `expenses`              | `/trips/{id}/expenses`     | Expenses + balances                                                  |
| `privacy`               | `/privacy`                 | Visibility scope, share window, audit log read                       |
| `recap`                 | `/trips/{id}/recap`        | Post-trip stats from the locations hypertable                        |
| `reminders`             | `/trips/{id}/reminders`    | Custom reminders CRUD + `.ics` export                                |
| `events`                | `/events`                  | Client telemetry ingest → TimescaleDB `events` hypertable            |
| `user_stats`            | `/me/stats`                | Personal wrapped-style stats                                         |
| `billing`               | `/billing`                 | Subscription create + status                                         |
| `admin_analytics`       | `/admin/analytics`         | Battery drain, provider health, ETA accuracy, WS lifetimes           |
| `admin_business`        | `/admin/business`          | MRR, funnel, churn                                                   |
| **`hazards`**           | **`/hazards`**             | **NASA EONET fan-out with optional `bbox=s,w,n,e` and `categories=csv`** |
| `trips_ws` (WebSocket)  | `/ws/trips/{id}`           | Live location + chat + typing + safety + ghost fan-out per trip      |

## Data stores

- **Postgres 16 + PostGIS** — users, trips, trip_members, waypoints (`geography(point, 4326)`), messages, expenses, subgroups, subscriptions, devices, audit, reminders, safety events.
- **TimescaleDB hypertables** — `locations` (high-write GPS stream), `events` (product analytics), `maps_provider_calls` (ops telemetry).
- **Redis** — `trip:{id}` pub/sub channel, `trip:{id}:online` presence set, OTP nonces (5 min TTL), slowapi buckets, `eonet:v1:global` hazard cache (15 min TTL).

CI spins up all three extensions (`postgis`, `timescaledb`, `pgcrypto`) against a `timescale/timescaledb-ha:pg16` service container — see the `alembic` job in `.github/workflows/ci.yml` for the bootstrap SQL reference.

## Auth pattern

- **Phone OTP** — `POST /auth/otp/request` (slowapi: 5/min/phone) writes a nonce to Redis with a 5-minute TTL; `POST /auth/otp/verify` (slowapi: 10/5min/phone + progressive cooldown after 3 failures) mints an access (15 min) + refresh (30 day) JWT pair.
- **Rotating refresh** — every `POST /auth/refresh` issues a fresh refresh token and invalidates the old one.
- **`current_user` dependency** — every protected route depends on `deps.current_user`; 401 if token missing or invalid.
- **`require_trip_member`** — trip-scoped routes additionally depend on this; 403 if the caller is not in the trip.
- **`require_admin`** — `/admin/*` routes depend on `deps.require_admin`, backed by the `users.is_admin` column added in migration `0003_admin_role.py`.
- **WebSocket handshake** — the token is passed as `?token=<jwt>` on `/ws/trips/{id}`, validated on connect before the pod subscribes to the Redis channel.

## Rate limiting

`slowapi` exposes a single process-local `Limiter` from `app/rate_limit.py`. The key function prefers a `phone` field cached on `request.state._phone_key` (so OTP limits are per-phone, not per-IP) and falls back to `get_remote_address(request)`.

Current limits:

| Route                      | Limit              | Key       |
| -------------------------- | ------------------ | --------- |
| `POST /auth/otp/request`   | 5/minute           | phone     |
| `POST /auth/otp/verify`    | 10/5minute         | phone     |
| `GET /hazards`             | 60/minute          | IP        |

Other endpoints have no explicit cap yet — a future sweep will tune per-route buckets. The global default is `60/minute` per IP where unspecified.

## Tests

```bash
pytest apps/backend/tests -q
```

`tests/conftest.py` isolates each test with an in-memory `fakeredis.aioredis` instance installed into `app.redis._client` via monkeypatch. `tests/test_hazards.py` mocks upstream httpx calls with `respx` and exercises:

1. first call populates the cache and returns a list
2. second call is served from cache (upstream hit count == 1)
3. bbox filter drops out-of-region hazards
4. category filter drops non-matching hazards
5. bbox + category filters compose
6. upstream failure with an empty cache → 503 with `{error: "eonet_unreachable"}`

### Known gap

The pytest deps (`pytest`, `pytest-asyncio`, `respx`, `fakeredis`) live in the dev environment only — they are **not** in `requirements.txt`, and CI does not yet run `pytest`. A Session 4 task should:

1. Add `requirements-dev.txt` with the test deps.
2. Add a `pytest` job to `.github/workflows/ci.yml` that `pip install`s both requirement files and runs `pytest apps/backend/tests -q`.

Until that lands, CI only runs `ruff check app` + a FastAPI import smoke test.

## Conventions

- **Every query is async.** SQLAlchemy 2 + asyncpg, no sync sessions.
- **Protected routes always depend on `current_user`** or `require_trip_member`. Never fish a user out of the raw JWT in route handlers.
- **Row-level access in the service layer.** Every query is scoped by `user_id` + `trip_id` membership. No raw SQL concat.
- **WebSocket messages use a typed envelope**: `{ "type": "...", ... }`. See `docs/ARCHITECTURE.md §5` for the full frame list.
- **No secrets in code.** Provider keys live in `app/config.py`, sourced from environment variables.
- **`loguru` for logging** with `trip_id` / `user_id` / `request_id` attached where available.

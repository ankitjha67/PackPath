# PackPath Backend

FastAPI + PostgreSQL (PostGIS + TimescaleDB) + Redis.

## Run locally

```bash
# 1. Start dependencies
cd ../../infra && docker compose up -d && cd -

# 2. Configure env
cp .env.example .env

# 3. Install deps
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# 4. Migrate
alembic upgrade head

# 5. Run
uvicorn app.main:app --reload --port 8000
```

Visit http://localhost:8000/docs for the auto-generated OpenAPI UI.

## Layout

```
app/
├── main.py              # FastAPI app factory
├── config.py            # Pydantic settings
├── logging.py           # loguru config
├── db.py                # async SQLAlchemy session
├── redis.py             # Redis client + pub/sub helpers
├── security.py          # JWT + password hashing
├── deps.py              # shared dependencies
├── models/              # SQLAlchemy models
├── schemas/             # Pydantic schemas
├── routers/             # REST endpoints
│   ├── auth.py
│   ├── trips.py
│   ├── waypoints.py
│   ├── messages.py
│   └── health.py
└── ws/
    └── trips.py         # /ws/trips/{trip_id}

alembic/
├── env.py
└── versions/
    └── 0001_initial.py  # core schema + TimescaleDB hypertable
```

## Conventions

- All DB access is async (SQLAlchemy 2 + asyncpg).
- Every protected route depends on `deps.current_user` → 401 if token missing/invalid.
- Trip-scoped routes additionally depend on `deps.require_trip_member`.
- WebSocket messages use the envelope `{ "type": "...", ... }` — see `docs/ARCHITECTURE.md`.

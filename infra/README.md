# infra

Local dev infrastructure for PackPath.

## What's in the box

- **Postgres 16** with **PostGIS** + **TimescaleDB** (single container via `timescaledb-ha:pg16`)
- **Redis 7** for pub/sub fan-out and OTP nonces

## Usage

```bash
docker compose up -d
docker compose logs -f
docker compose down          # stop
docker compose down -v       # stop + wipe volumes
```

Postgres is reachable at:

```
postgresql://packpath:packpath@localhost:5432/packpath
```

Redis at:

```
redis://localhost:6379
```

Extensions (`postgis`, `timescaledb`, `pgcrypto`) are auto-installed on first boot via `postgres/init/01_extensions.sql`.

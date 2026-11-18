#!/bin/sh
# Wait for Postgres, apply migrations, then run the given command (the API).
set -e

echo "[packpath] waiting for the database…"
python - <<'PY'
import os, time, socket, urllib.parse as u
dsn = os.environ.get("DATABASE_URL", "")
# Pull host/port out of a SQLAlchemy async URL like
# postgresql+asyncpg://user:pass@host:5432/db
host, port = "postgres", 5432
if "@" in dsn and "/" in dsn:
    try:
        netloc = dsn.split("@", 1)[1].split("/", 1)[0]
        hostpart = netloc.split("?", 1)[0]
        host = hostpart.split(":")[0] or host
        if ":" in hostpart:
            port = int(hostpart.split(":")[1])
    except Exception:
        pass
for _ in range(60):
    try:
        with socket.create_connection((host, port), timeout=2):
            break
    except OSError:
        time.sleep(1)
else:
    raise SystemExit(f"database at {host}:{port} never became reachable")
print(f"[packpath] database reachable at {host}:{port}")
PY

echo "[packpath] applying migrations…"
alembic upgrade head

echo "[packpath] starting API…"
exec "$@"

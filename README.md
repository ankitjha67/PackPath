# PackPath

> Group trip navigation, together. Live location, shared routes, chat, push-to-talk voice, and offline maps — for trips where everyone needs to stay in the pack.

PackPath fills the gap between Life360 (tracking, no nav), Google Maps (nav, no group view), and WhatsApp (chat, no maps). One app for a group heading somewhere together.

## Status

v1 in active development. Currently scaffolding foundation (Weekend 1–2).

## Monorepo layout

```
packpath/
├── apps/
│   ├── mobile/          # Flutter 3.x app (flutter_map + Mapbox)
│   └── backend/         # FastAPI + Postgres/PostGIS/TimescaleDB + Redis
├── infra/               # docker-compose for local dev
└── docs/                # PRD, ARCHITECTURE, ROADMAP
```

## Quick start — backend

```bash
cd infra
docker compose up -d                # Postgres + PostGIS + TimescaleDB + Redis

cd ../apps/backend
cp .env.example .env
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
alembic upgrade head
uvicorn app.main:app --reload
```

Health check: http://localhost:8000/healthz
Docs:         http://localhost:8000/docs

## Quick start — mobile

```bash
cd apps/mobile
flutter pub get
# Put your Mapbox public token into lib/config/env.dart (see env.example.dart)
flutter run
```

## Stack

| Concern        | Pick                                               |
| -------------- | -------------------------------------------------- |
| Mobile         | Flutter 3.x, flutter_map, Mapbox tiles             |
| Backend        | FastAPI (Python 3.11)                              |
| DB             | Postgres 16 + PostGIS + TimescaleDB (hypertables)  |
| Realtime       | WebSockets via FastAPI + Redis pub/sub for fan-out |
| Voice          | LiveKit (push-to-talk, WebRTC)                     |
| Maps / routing | Mapbox (tiles, offline, directions)                |
| Push           | Firebase Cloud Messaging                           |
| Auth           | Phone OTP (MSG91 / Twilio) + JWT                   |
| Infra          | Railway / Fly.io → AWS ECS at scale                |
| Payments       | Razorpay (IN) + Stripe (intl)                      |

See `docs/ARCHITECTURE.md` for the full picture.

## License

Proprietary — all rights reserved.

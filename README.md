# PackPath

> Group trip navigation, together. Live location, shared routes, chat, push-to-talk voice, and offline maps — for trips where everyone needs to stay in the pack.

PackPath fills the gap between Life360 (tracking, no nav), Google Maps (nav, no group view), and WhatsApp (chat, no maps). One app for a group heading somewhere together.

## Status

v1 shipped. v1.1 ("advanced features") in active development —
safety (SOS, crash, stranded, speed, fatigue), live link for non-
members, cost/weather/elevation enrichments, group dynamics, cost
split, privacy upgrades, voice multi-channel, trip recap, full
operational + product + business analytics, reminders, .ics export,
mobile screens for everything above. See `docs/PLAN_v1.1.md`.

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

| Concern        | Pick                                                          |
| -------------- | ------------------------------------------------------------- |
| Mobile         | Flutter 3.x, flutter_map, switchable tile provider             |
| Backend        | FastAPI (Python 3.11)                                          |
| DB             | Postgres 16 + PostGIS + TimescaleDB (hypertables)              |
| Realtime       | WebSockets via FastAPI + Redis pub/sub for fan-out             |
| Voice          | LiveKit (push-to-talk, WebRTC)                                 |
| Maps / routing | **Mapbox / Google / Mappls / HERE / TomTom / OSRM** (resolver) |
| Push           | Firebase Cloud Messaging                                       |
| Auth           | Phone OTP (MSG91 / Twilio) + JWT                               |
| Infra          | Railway / Fly.io → AWS ECS at scale                            |
| Payments       | Razorpay (IN) + Stripe (intl)                                  |

### Maps providers

PackPath ships with a provider abstraction so the routing/ETA pipeline can talk to any major maps API and chain fallbacks. Pick the default with `MAPS_PROVIDER` and chain alternates with `MAPS_FALLBACK_PROVIDERS`.

| Provider | id        | Server env keys                                              |
| -------- | --------- | ------------------------------------------------------------ |
| Mapbox   | `mapbox`  | `MAPBOX_SERVER_TOKEN`                                        |
| Google   | `google`  | `GOOGLE_MAPS_API_KEY`                                        |
| Mappls   | `mappls`  | `MAPPLS_CLIENT_ID`, `MAPPLS_CLIENT_SECRET`, `MAPPLS_REST_KEY`|
| HERE     | `here`    | `HERE_API_KEY`                                               |
| TomTom   | `tomtom`  | `TOMTOM_API_KEY`                                             |
| OSRM     | `osrm`    | `OSRM_BASE_URL` (defaults to public demo)                    |

`GET /maps/providers` lists what's actually configured on the server (no secrets) so the mobile client can render an honest tile-layer picker.

See `docs/ARCHITECTURE.md` for the full picture.

## License

Proprietary — all rights reserved.

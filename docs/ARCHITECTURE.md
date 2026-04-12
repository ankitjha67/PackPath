# PackPath — Architecture

**Status:** v1 draft
**Last updated:** 2026-04-12

This document captures the technical design of PackPath v1 using a lightweight C4-style progression (Context → Containers → Components). Detailed ADRs live in `docs/adr/` (added as they happen).

---

## 1. C4 Level 1 — System context

```
                  ┌────────────────────────┐
                  │      End user          │
                  │  (trip member, owner)  │
                  └───────────┬────────────┘
                              │
                              ▼
                  ┌────────────────────────┐
                  │      PackPath app      │
                  │   (Flutter, iOS/And)   │
                  └───────────┬────────────┘
                              │  HTTPS / WSS
                              ▼
         ┌────────────────────────────────────────┐
         │          PackPath backend              │
         │       (FastAPI, WebSocket, Redis)      │
         └──┬────────┬──────────┬─────────┬───────┘
            │        │          │         │
            ▼        ▼          ▼         ▼
         ┌─────┐  ┌─────┐   ┌──────┐  ┌──────┐
         │ PG/ │  │ TS  │   │ FCM  │  │Mapbox│
         │PostGIS│ │DB   │ │push  │  │tiles │
         └─────┘  └─────┘   └──────┘  └──────┘
                              │
                              ▼
                          ┌───────┐
                          │LiveKit│
                          │ (PTT) │
                          └───────┘
```

External systems:
- **Mapbox** — tile service, offline downloads, Directions API
- **Firebase Cloud Messaging** — push notifications
- **LiveKit Cloud** — push-to-talk rooms (WebRTC SFU)
- **MSG91** — phone OTP delivery (Twilio as global fallback)
- **Razorpay / Stripe** — subscription billing

## 2. C4 Level 2 — Containers

```
Flutter app
  ├── presentation (screens, widgets)
  ├── state (Riverpod providers)
  ├── services (api client, ws client, location, mapbox, livekit)
  └── storage (Hive: offline queue, trip cache)

FastAPI backend
  ├── API (REST: auth, trips, waypoints, messages)
  ├── WebSocket gateway (/ws/trips/{id})
  ├── Auth (JWT, refresh, OTP)
  ├── Background workers (geofence, eta refresh)
  └── Data access (SQLAlchemy 2.x async, Alembic)

Data stores
  ├── Postgres 16 + PostGIS (users, trips, members, waypoints, messages)
  ├── TimescaleDB (locations hypertable — high write, time-bucketed reads)
  └── Redis (pub/sub channels `trip:{id}`, rate limits, OTP nonces)
```

## 3. Realtime flow — location fan-out

```
member A phone ──► WSS ──► FastAPI pod #1 ──► Redis PUB trip:42
                                                      │
                                                      ▼
                                              Redis SUB fan-out
                                                      │
                             ┌────────────────────────┼────────────────────────┐
                             ▼                        ▼                        ▼
                     FastAPI pod #1           FastAPI pod #2           FastAPI pod #3
                             │                        │                        │
                             ▼                        ▼                        ▼
                       member B/C             members D/E              member F
```

- One Redis channel per trip: `trip:{trip_id}`.
- Backend pods subscribe lazily — only when the pod holds ≥1 WS client for that trip.
- This lets us scale the backend horizontally behind Fly.io / Railway without sticky sessions.
- Location points are **also** persisted to the TimescaleDB `locations` hypertable for history + recap.

## 4. Data model (core)

```sql
-- users
id uuid pk
phone text unique
display_name text
avatar_url text
created_at timestamptz

-- trips
id uuid pk
owner_id uuid fk users
name text
status text check (status in ('planned','active','ended','cancelled'))
start_at timestamptz
end_at timestamptz
join_code char(6) unique
created_at timestamptz

-- trip_members
trip_id uuid fk trips
user_id uuid fk users
role text check (role in ('owner','member'))
color text
joined_at timestamptz
left_at timestamptz
ghost_mode bool default false
primary key (trip_id, user_id)

-- waypoints
id uuid pk
trip_id uuid fk trips
position int
name text
geom geography(point, 4326)
arrival_radius_m int default 150
created_at timestamptz

-- locations (TimescaleDB hypertable)
user_id uuid
trip_id uuid
geom geography(point, 4326)
heading real
speed_mps real
battery_pct smallint
recorded_at timestamptz
primary key (user_id, trip_id, recorded_at)

-- messages
id uuid pk
trip_id uuid fk trips
user_id uuid fk users
body text
kind text check (kind in ('text','system','arrival','leave','join'))
sent_at timestamptz

-- devices (FCM tokens)
id uuid pk
user_id uuid fk users
fcm_token text unique
platform text
last_seen_at timestamptz
```

PostGIS indexes on `waypoints.geom` (GIST) and on the hypertable (space-partitioning by trip bucket).

## 5. API surface — v1

### REST

| Method | Path                              | Purpose                                |
| ------ | --------------------------------- | -------------------------------------- |
| POST   | `/auth/otp/request`               | Send OTP to phone                      |
| POST   | `/auth/otp/verify`                | Verify OTP → JWT access + refresh      |
| POST   | `/auth/refresh`                   | Refresh access token                   |
| GET    | `/me`                             | Current user                           |
| PATCH  | `/me`                             | Update profile                         |
| POST   | `/trips`                          | Create trip                            |
| GET    | `/trips`                          | List my trips                          |
| GET    | `/trips/{id}`                     | Trip detail incl. members, waypoints   |
| POST   | `/trips/{id}/join`                | Join via code                          |
| POST   | `/trips/{id}/leave`               |                                        |
| POST   | `/trips/{id}/end`                 | Owner ends trip → triggers auto-expire |
| POST   | `/trips/{id}/waypoints`           | Add waypoint                           |
| PATCH  | `/trips/{id}/waypoints/{wp}`      |                                        |
| DELETE | `/trips/{id}/waypoints/{wp}`      |                                        |
| GET    | `/trips/{id}/messages`            | Paginated chat history                 |
| POST   | `/trips/{id}/messages`            | Send message (also available via WS)   |
| POST   | `/trips/{id}/locations`           | Bulk sync offline-queued points        |
| GET    | `/trips/{id}/recap`               | Trip summary                           |

### WebSocket

`GET /ws/trips/{trip_id}?token=<jwt>`

Inbound messages (client → server):
```json
{ "type": "location", "lat": 28.61, "lng": 77.20, "hdg": 214, "spd": 12.5, "bat": 82, "t": "2026-04-12T06:10:00Z" }
{ "type": "message",  "body": "5 min out" }
{ "type": "typing",   "state": "start" }
{ "type": "ghost",    "on": true }
```

Outbound (server → client):
```json
{ "type": "location", "user_id": "...", "lat": 28.61, ... }
{ "type": "message",  "user_id": "...", "body": "..." }
{ "type": "presence", "user_id": "...", "state": "joined" }
{ "type": "arrival",  "user_id": "...", "waypoint_id": "..." }
```

## 6. Auth

- Phone + OTP via MSG91 (Twilio fallback).
- Backend stores only `phone` + `hashed_otp_nonce` (Redis, 5 min TTL).
- Successful verify mints a 15-minute access JWT + 30-day refresh JWT.
- Refresh tokens are rotating; revoked-on-refresh.
- WS auth: token passed in query param, validated on handshake, enforced per-pod.

## 7. Battery strategy (the one that matters)

- Android: `FusedLocationProvider` with adaptive `LocationRequest`:
  - Moving fast (>10 km/h): 5 s interval, high accuracy.
  - Walking / slow: 15 s, balanced.
  - Stationary >2 min: 30 s, low-power.
  - Battery <15% or charging off: pause, resume with next significant change.
- iOS: foreground uses standard CL updates; background uses **significant location changes** API only.
- Wire format: deltas compressed client-side, batched every 15 s over WS.
- Server rate-limits writes to 1 Hz per user per trip.

## 8. Offline

- Tiles: Mapbox Maps SDK offline region around the route corridor at trip creation.
- App-side durable queue (Hive) for locations + chat messages while offline.
- On reconnect: bulk `POST /trips/{id}/locations`, re-hydrate WS, replay queued chats.

## 9. Observability

- Structured JSON logs (loguru) with `trip_id`, `user_id`, `request_id`.
- Prometheus metrics: WS connections, location write latency, fan-out lag, pg query p95.
- Sentry for crashes (mobile + backend).

## 10. Security

- All traffic TLS. No plaintext WS.
- Row-level access enforced in service layer: every query is scoped by `user_id` + `trip_id` membership.
- PostGIS queries parameterized; no string concat.
- Rate limits per phone / per IP on OTP.
- Privacy dashboard in-app shows exactly what's stored.

## 11. Defaults and decisions (Critical Thinker)

| Decision                                  | Choice                                    | Why                                                               |
| ----------------------------------------- | ----------------------------------------- | ----------------------------------------------------------------- |
| Flutter `flutter_map` vs Mapbox SDK       | Both — `flutter_map` for base, Mapbox SDK for offline tiles | `flutter_map` is widget-friendly; Mapbox SDK owns offline tiles  |
| WebSocket vs MQTT                         | WebSocket                                  | FastAPI native, fewer moving parts, LiveKit already bundles WebRTC |
| Redis vs Kafka for fan-out                | Redis pub/sub                              | Low volume per trip, no replay needed, simpler ops               |
| Postgres vs separate time-series DB       | Postgres+TimescaleDB extension             | One DB, hypertables give us time-series performance              |
| JWT vs session cookies                    | JWT (access+refresh, rotating)             | Mobile-first, stateless backend, easy WS auth                    |
| Monorepo vs polyrepo                      | Monorepo                                   | Solo dev, atomic cross-cutting changes                           |
| Alembic vs SQLModel auto                  | Alembic                                    | Explicit migrations are safer at product stage                   |

---

Open ADRs: offline conflict resolution, LiveKit self-host trigger point, geofence evaluation location (client vs server).

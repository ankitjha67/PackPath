# PackPath v1.1 — Advanced features & analytics

Plan for the second wave on top of the v1 monorepo. Built on the same
FastAPI + Postgres+PostGIS+TimescaleDB + Redis + Flutter stack — no new
infrastructure.

## Bundles

### 1 · Schema (Alembic 0002)
New columns + new tables for everything below.
- `trip_members.visibility_scope` (text), `share_until` (timestamptz),
  `subgroup_id`, `vehicle_label`, `is_ready` (bool)
- `trips.template`, `trips.cover_color`
- `audit_logs` table
- `expenses`, `expense_shares` tables
- `subgroups` table
- `subscriptions` table
- `reminders` table
- `events` table — TimescaleDB hypertable for product telemetry
- `safety_alerts` table — SOS, crash, stranded, fatigue, speed events

### 2 · Safety
- WS frame `{type:"sos"}` + full-screen alert sheet on every peer
- WS frame `{type:"crash"}` from accelerometer (sensors_plus) with
  10 s cancel countdown
- Server-side stranded detection cron (`battery<10% & no movement
  >15 min & not at a waypoint`)
- Speed alert nudges in chat
- Driver fatigue heuristic (`drive_time + speed_variance` rolling)
- All five persisted to `safety_alerts` table

### 3 · Live link
- `POST /trips/{id}/livelink` mints a short-lived JWT scoped to a
  read-only view of the trip
- `GET /public/livelink/{token}` serves a minimal map snapshot (members,
  current ETA) without requiring auth
- Mobile share screen gets a "Share live view" tab

### 4 · Smart routing
- `services/cost.py` — fuel + toll cost estimator from route distance,
  vehicle profile, region tolls table
- `services/weather.py` — weather samples along the polyline
  (OpenWeatherMap, no key required falls back to mock)
- `services/elevation.py` — elevation profile via Mapbox Terrain RGB or
  Open-Elevation
- Convoy re-route logic in `services/maps/registry.py` — if any member
  drops > X km behind median, suggest a meet-up waypoint
- `POST /trips/{id}/directions/alternates` returns 3 alternative routes

### 5 · Group dynamics
- Roles enum on `trip_members.role`: owner, driver, navigator, dj,
  photographer, treasurer
- `POST /trips/{id}/ready_check` toggles a per-member readiness, with a
  derived `all_ready` field
- Sub-groups CRUD (`POST /trips/{id}/subgroups`) — own chat lane and
  PTT room per sub-group
- Trip templates: hardcoded list served via `GET /trip_templates`,
  applied at trip creation

### 6 · Cost split
- `expenses` + `expense_shares` tables
- `POST /trips/{id}/expenses` add expense, split equally or weighted
- `GET /trips/{id}/balances` per-member net balance
- Mobile expenses screen: list + add + show "you owe / you're owed"

### 7 · Privacy upgrades
- `trip_members.visibility_scope` jsonb (`{type:"all"|"some","user_ids":[...]}`
- `trip_members.share_until` timestamptz — auto-stop sharing
- `audit_logs` write on every WS read
- `GET /me/audit` paginated audit log
- Privacy dashboard mobile screen extended to show audit log

### 8 · Voice multi-channel
- `POST /trips/{id}/voice/token?channel=drivers|everyone|<subgroup_id>`
- Each channel mints a different LiveKit room

### 9 · Trip recap
- `GET /trips/{id}/recap` server-computed stats from the locations
  hypertable: total km, top speed, avg speed, elevation gain, time
  of day heatmap, member roster
- Mobile recap screen with shareable card layout

### 10 · Operational analytics
- New `routers/admin/analytics.py` (placeholder auth) with these
  endpoints, all from TimescaleDB:
  - Battery drain per device per hour
  - WS connection lifetimes (p50/p95/p99)
  - Reconnect frequency
  - Geofence trigger latency
  - Maps provider health (count, error rate, p95)
  - ETA accuracy (predicted vs actual at arrival)

### 11 · Product analytics
- `events` TimescaleDB hypertable with `(user_id, name, properties,
  created_at)`
- `POST /events` accepts a batched array
- Mobile `EventLogger` service auto-captures key events

### 12 · User stats
- `GET /me/stats` returns personal stats
- Mobile personal stats screen pulled from /me/stats

### 13 · Business analytics
- `subscriptions` table (provider, plan, status, MRR contribution)
- `GET /admin/business/mrr` daily MRR
- `GET /admin/business/funnel` conversion funnel by paywall surface

### 14 · Reminders + calendar export
- `reminders` table — scheduled message generation cron
- `POST /trips/{id}/reminders` add custom reminder
- `GET /trips/{id}/calendar.ics` generates an .ics for the trip

### 15 · Mobile event logger
- Auto-fires events for every funnel step from app start through trip
  end. Buffered in a small Hive box, flushed periodically.

## What's deliberately NOT in this drop

- Apple Watch / Wear OS / CarPlay (new platform integrations)
- Strava export (OAuth dance + new package)
- Spotify integration (OAuth)
- Voice transcription (cost-prohibitive without budget)
- Auto-album face detection
- ML-based ETA refinement (needs training data)

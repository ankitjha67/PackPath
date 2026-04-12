# PackPath — Roadmap

6 weekends to v1 + polish week. Solo-shipped.

## Weekend 1–2 — Foundation (in progress)

- [x] Monorepo layout (`apps/mobile`, `apps/backend`, `infra`, `docs`)
- [x] PRD, Architecture, Roadmap docs
- [x] `docker-compose.yml` for Postgres+PostGIS, TimescaleDB, Redis
- [x] FastAPI skeleton: settings, logging, healthcheck, error handlers
- [x] SQLAlchemy 2.x async models for core data model
- [x] Alembic migrations (initial schema + hypertable)
- [x] Phone-OTP auth stub (`/auth/otp/request`, `/auth/otp/verify`, JWT issue/refresh)
- [x] Trip CRUD + join-by-code
- [x] WebSocket endpoint `/ws/trips/{trip_id}` with Redis pub/sub fan-out
- [x] Flutter skeleton: go_router, Riverpod, theming
- [x] Mapbox map screen (base tiles)
- [x] Login → OTP → trip list → trip map flow wired as stubs

## Weekend 3 — Live map (in progress)

- [x] Location service on device (`AdaptiveLocationService`, geolocator)
- [x] Client WebSocket bridge (`TripSocket` + `LiveTripController`)
- [ ] Hive offline queue for outbound location frames
- [x] Broadcast location adaptively (5 s moving / 15 s walking / 30 s stationary, suspend <15% battery)
- [x] Render member avatars with battery + per-member color
- [x] Android + iOS location/voice/camera permission manifests
- [ ] Heading arrow + smooth marker interpolation
- [ ] "Follow me" and "frame all" camera controls
- [ ] Battery-drain benchmark (target <4%/hour)

## Weekend 4 — Routes + ETA (in progress)

- [x] Long-press to add waypoint
- [ ] Waypoint list drawer, drag to reorder
- [x] Mapbox Directions backend proxy (token never leaves the server)
- [x] Polyline render on map (real route, falls back to dashed straight line)
- [ ] Per-member ETA panel
- [ ] Share trip via deep link + QR

## Weekend 5 — Chat + push

- [ ] WS chat (new message type) + persistence
- [ ] Chat screen with typing indicators
- [ ] FCM integration (backend send, client register)
- [ ] Background push for messages
- [ ] Server-side geofence evaluation → `arrival` system messages

## Weekend 6 — Voice + offline

- [ ] LiveKit room provisioning per trip (backend token mint)
- [ ] PTT button UI + hold-to-talk
- [ ] Mapbox offline region download for route corridor
- [ ] Offline-to-online sync validation (pull-the-cable test)

## Polish week

- [ ] Trip history list, share recap image
- [ ] Dark mode
- [ ] Privacy dashboard screen
- [ ] Razorpay / Stripe subscription screen
- [ ] Google Play + App Store assets + listings
- [ ] Landing page (packpath.app) with waitlist

## Later (v1.1+)

- [ ] Apple Watch companion PTT
- [ ] Trip templates (weekly carpool, daily school run)
- [ ] Web viewer for non-installing passengers
- [ ] OSRM self-host when Mapbox MAU > 40k
- [ ] LiveKit self-host when trip-hours > 20k/month

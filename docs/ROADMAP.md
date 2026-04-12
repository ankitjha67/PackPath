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

## Weekend 3 — Live map (done bar benchmark)

- [x] Location service on device (`AdaptiveLocationService`, geolocator)
- [x] Client WebSocket bridge (`TripSocket` + `LiveTripController`)
- [x] Hive offline queue for outbound location frames (auto-drain on reconnect)
- [x] Broadcast location adaptively (5 s moving / 15 s walking / 30 s stationary, suspend <15% battery)
- [x] Render member avatars with battery + per-member color
- [x] Android + iOS location/voice/camera permission manifests
- [x] Heading arrow on member markers
- [x] "Follow me" FAB and "Frame everyone" camera controls
- [ ] Battery-drain benchmark (target <4%/hour) — needs a real device

## Weekend 4 — Routes + ETA (mostly done)

- [x] Long-press to add waypoint
- [x] Waypoints drawer (delete via swipe; reorder pending bulk endpoint)
- [x] Mapbox Directions backend proxy (token never leaves the server)
- [x] Polyline render on map (real route, falls back to dashed straight line)
- [x] Per-member ETA panel (backend `/etas`, mobile bottom sheet)
- [x] Share trip via QR (deep-link `packpath://join/<code>`, universal link wiring in polish week)

## Weekend 5 — Chat + push (done)

- [x] Trip WebSocket persists `message` frames into the messages table
- [x] Chat screen with REST history + live WS frames + optimistic local echo
- [x] Typing indicators (WS `typing` frame, idle-aware client, in-chat banner)
- [x] FCM device registration endpoint (`POST /devices`)
- [x] FCM send-on-message hook (`services/push.py`, presence-aware via Redis SET)
- [x] FCM client init + token registration on OTP verify
- [x] Server-side geofence arrival → system `arrival` chat message + WS fan-out

## Weekend 6 — Voice + offline (in progress)

- [x] LiveKit token mint endpoint (`POST /trips/{id}/voice/token`, JWT in-process)
- [x] Mobile `VoiceService` + hold-to-talk `PttButton` (livekit_client)
- [x] One LiveKit room per trip (`trip-{trip_id}`), muted by default
- [x] Hive-backed Mapbox tile cache + `CachedMapboxTileProvider`
- [x] Offline tile prefetcher with bbox + zoom range, run from the trip map menu
- [ ] Cellular-aware download throttling (don't burn data on metered networks)
- [ ] Self-hosted LiveKit deployment (parked until v1.1)

## Weekend 6 — Voice + offline

- [ ] LiveKit room provisioning per trip (backend token mint)
- [ ] PTT button UI + hold-to-talk
- [ ] Mapbox offline region download for route corridor
- [ ] Offline-to-online sync validation (pull-the-cable test)

## Maps providers (shipped)

- [x] Provider abstraction in `app/services/maps/` with a normalized `RouteResult`
- [x] Mapbox, Google, Mappls (MapmyIndia), HERE, TomTom, OSRM
- [x] Resolver picks default from `MAPS_PROVIDER` (or auto-detects), chains `MAPS_FALLBACK_PROVIDERS`
- [x] `directions` and `etas` routers go through the resolver — no more Mapbox-only
- [x] `GET /maps/providers` returns `{default, fallback_chain, providers[]}` so the client can render an honest tile-layer picker
- [x] Mobile tile-layer switcher with persisted user choice (`SharedPreferences`)
- [x] Per-provider attribution

## Polish week (in progress)

- [x] Trip history (Active / Past tabs on the trip list screen)
- [ ] Trip recap image (renderable share card)
- [x] Dark mode (`ThemeMode.system` since v1)
- [x] Privacy dashboard screen
- [x] Plans / subscription screen (stub — Razorpay + Stripe flow lands later)
- [x] Free-tier limit enforcement on backend (5 members, 24h windows)
- [x] Ghost mode end-to-end (toggle, server-side fan-out suppression, banner)
- [x] CI: ruff lint + import smoke + flutter analyze + alembic against
      Postgres+PostGIS+TimescaleDB
- [ ] `flutter create .` to inject the gradle/Xcode wrapping projects
- [ ] Universal-link handler for `packpath://join/<code>`
- [ ] Real-device battery-drain benchmark
- [ ] Google Play + App Store assets + listings
- [ ] Landing page (packpath.app) with waitlist

## Later (v1.1+)

- [ ] Apple Watch companion PTT
- [ ] Trip templates (weekly carpool, daily school run)
- [ ] Web viewer for non-installing passengers
- [ ] OSRM self-host when Mapbox MAU > 40k
- [ ] LiveKit self-host when trip-hours > 20k/month

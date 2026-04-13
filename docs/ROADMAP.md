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

## v1.1 — Advanced features (in progress)

See `docs/PLAN_v1.1.md` for the bundle breakdown.

- [x] Schema migration `0002_advanced_features` (visibility scope, sub-groups, expenses, subscriptions, reminders, audit, safety, events hypertable, maps_provider_calls hypertable)
- [x] **Safety**: SOS frame, crash detection (`sensors_plus`), server-side stranded + speed detection, full-screen safety alert sheet
- [x] **Live link** for non-members: `POST /trips/{id}/livelink` mints a JWT, `GET /public/livelink/{token}` serves a stripped read-only snapshot
- [x] **Smart routing**: cost / weather / elevation enrichments on `POST /trips/{id}/directions`, dedicated `/cost` shortcut
- [x] **Group dynamics**: roles, ready-check, sub-groups CRUD + join, hardcoded trip templates
- [x] **Cost split**: expenses + balances, equal or weighted shares, integer cents
- [x] **Privacy upgrades**: per-member visibility scope, time-boxed `share_for`, audit log
- [x] **Voice multi-channel**: `POST /trips/{id}/voice/token?channel=...` mints a per-channel LiveKit room
- [x] **Trip recap**: server-computed stats from the locations hypertable + mobile recap screen
- [x] **Operational analytics**: `/admin/analytics/{battery_drain,maps_provider_health,eta_accuracy,ws_lifetimes}`
- [x] **Product analytics**: `POST /events` ingest + Hive-buffered mobile EventLogger
- [x] **Personal stats**: `GET /me/stats` + mobile Wrapped-style screen
- [x] **Business analytics**: `/admin/business/{mrr,funnel,churn}` + subscription create endpoint
- [x] **Reminders + .ics export**: `GET /trips/{id}/calendar.ics`, custom reminders CRUD
- [x] Mobile: SOS button, crash detector, recap screen, expenses screen, audit log screen, personal stats screen, safety alert sheet wired into the trip map

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

## Session 3 status

The existing "Weekend" structure above described v1 delivery; Sessions 2+ use a Track-based breakdown so we can ship visual, backend, and quality work in parallel without blocking each other.

### Session 3 Track 1 — quality pass (PR #5, merged)

Follow-up on the Session 2 radar-map restyle. Every finding logged in `docs/SESSION2_FINDINGS.md` resolved.

- [x] typed the waypoint list — `List<WaypointDto>` everywhere, no more dynamic `List` + `w.latLng as LatLng` duck-typing
- [x] `Color.withOpacity` → `Color.withValues(alpha:)` sweep across the whole codebase
- [x] `EtaPanel` modal: added `useSafeArea: true` so the drag handle can't slip under the status-bar notch
- [x] themed the cloud-status indicator in the app bar on `colorScheme.tertiary` / `colorScheme.error` / `colorScheme.secondary` instead of hardcoded Material color shortcuts
- [x] ETA panel member row: dropped the fabricated `Member abc123` label in favour of a leading dot pulled from `tripDetailProvider` + the raw user id prefix as a technical disambiguator
- [x] PTT button: subtle scale pulse while `_talking == true` via `SingleTickerProviderStateMixin` + `ScaleTransition`

### Session 3 Track 2 — NASA EONET hazard integration (PR #6, merged)

End-to-end hazard feature, backend + mobile.

- [x] backend `/hazards` router with `?bbox=s,w,n,e` + `?categories=csv` filters and a `slowapi` 60/min/IP bucket
- [x] `app/services/eonet_service.py` fetches EONET v3, normalizes to an internal `Hazard` shape, caches globally in Redis at `eonet:v1:global` with a 15-minute TTL
- [x] severity inference from earthquake magnitude and wildfire polygon presence; everything else falls through to a per-category baseline
- [x] stale-cache fallback on EONET 5xx; 503 only when the cache is truly empty
- [x] pytest suite against `fakeredis` + `respx` exercising cache miss, cache hit, bbox filter, category filter, compose, upstream failure
- [x] Flutter `HazardDto` + sealed `GeometryDto` (Point / Polygon) with safe `fromJson`
- [x] `HazardsRepository` + `tripHazardsProvider` (FutureProvider.family with a `Timer.periodic(5 min)` loop and `ref.onDispose(timer.cancel)`)
- [x] `HazardLayer` MarkerLayer with category→icon/color map and a tap-to-open bottom sheet
- [x] `hazard_proximity.dart` per-category kilometre buffer check (haversine for Points, ray-cast point-in-polygon for Polygons)
- [x] `HazardBanner` slide-down alert via `AnimatedSlide` + `AnimatedOpacity`, dismissal keyed on the set of hazard ids so a new hazard re-shows automatically
- [x] three-layer MarkerLayer split in `trip_map_screen.dart` so hazards render between members and waypoints

### Session 3 Track 2.5 — documentation audit + refresh (this PR)

- [x] refreshed root `README.md` against the current feature set (added hazards, Kinetic Path, onboarding, expense split, recap, audit, the actual Flutter pin)
- [x] rewrote `apps/backend/README.md` with the full app layout, env vars, router table, slowapi limits, and the pytest-deps-not-in-requirements known gap
- [x] rewrote `apps/mobile/README.md` with the Flutter 3.41.4 pin and google_fonts story, the actual `lib/features/*` layout including `hazards/`, Mapbox token split, Windows kotlin.incremental gotcha, pre-commit rules, stubbed-push gap
- [x] marked `docs/SESSION2_FINDINGS.md` as resolved in PR #5
- [x] appended a Session 3 section to `docs/ARCHITECTURE.md` covering the EONET data flow + severity + buffers and the design-system hardening narrative
- [x] appended this Session 3 status block to `docs/ROADMAP.md`

### Session 3 Track 3 — MVP screens (pending)

- [ ] fill in any missing screens identified by the Session 3 audit
- [ ] bind every feature router to a real mobile surface (some still land on stubs)
- [ ] polish the onboarding → login → trip list → trip map happy path

## Session 4 (planned)

Stretch goals for the next session. Ordering is rough and will shift based on what bites first.

- [ ] **FCM push for hazard alerts** — fire a push when a new hazard lands inside a user's active-trip proximity buffer; will land on top of the existing `services/push.py` fan-out
- [ ] **pytest job in CI** — add `requirements-dev.txt` with `pytest`, `pytest-asyncio`, `respx`, `fakeredis`, and a pytest job to `.github/workflows/ci.yml` so `tests/test_hazards.py` blocks merges
- [ ] **real Firebase project** — run `flutterfire configure` with a real project, drop the stub `google-services.json` / `GoogleService-Info.plist` / `firebase_options.dart`
- [ ] **E2E smoke test** — at minimum an `integration_test` that runs through onboarding → OTP → create trip → see the map, so regressions can't silently ship
- [ ] **Android cmdline-tools emulator fix** — the current local setup can't boot an emulator without a manual cmdline-tools install; document or scriptify
- [ ] **real-device battery-drain benchmark** — the v1 roadmap's one remaining open checkbox

## Session 5 (planned)

Ship-readiness pass. None of this is blocking earlier work but it's all on the critical path before a public beta.

- [ ] **privacy policy** copy and hosted page
- [ ] **terms of service** copy
- [ ] **store assets** — icon, feature graphic, screenshots, short + long description for Google Play and the App Store
- [ ] **app icon** — currently the default Flutter launcher icon
- [ ] **production environment** — Railway (or Fly.io) deployment with a hardened `.env`, real secrets, observability wiring
- [ ] **beta tester cohort** — TestFlight + Play internal test track, feedback loop

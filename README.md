# PackPath

> Group navigation for coordinated trips. Real-time member location, push-to-talk voice, shared waypoints, per-member ETA, offline tiles, NASA EONET hazard alerts, expense splitting, trip recaps. Flutter on iOS + Android, FastAPI backend, freemium (Pro tier at ₹149 / $2.99 planned).

PackPath fills the gap between Life360 (tracking, no nav), Google Maps (nav, no group view), and WhatsApp (chat, no maps). One app for a group heading somewhere together.

## Current feature set (shipped, on `main`)

Everything in this list is live in `main` today and merges into every build. For aspirational items see `docs/ROADMAP.md`.

- **Auth** — phone OTP with JWT access + rotating refresh tokens.
- **Trips** — create, join by 6-char code, invite via `packpath://join/<code>` deep link, end, ghost mode.
- **Real-time member locations** — WebSocket fan-out via Redis pub/sub, TimescaleDB hypertable for history, adaptive client-side GPS sampling, heading arrow + battery arc per member.
- **Shared waypoints** — long-press on the map to add; reorder via swipe in the waypoints drawer.
- **Map tiles** — Mapbox primary + OSM fallback, Hive-backed offline tile cache, bbox prefetcher.
- **Per-member ETA** — `POST /trips/{id}/directions` proxies to Mapbox / Google / Mappls / HERE / TomTom / OSRM via a single resolver; ETA bottom sheet computes every member's arrival at the next waypoint.
- **LiveKit push-to-talk voice** — one room per trip, hold-to-talk gesture with pulse animation while broadcasting.
- **In-trip chat** — REST history + WS live frames, typing indicators, optimistic local echo, geofenced `arrival` system messages.
- **Expense splitting** — equal or weighted shares, integer cents, per-trip balance ledger.
- **Trip recap** — distance, moving time, stops, top speed, hour-of-day heatmap computed from the locations hypertable.
- **Onboarding** — 3-pillar Kinetic Path intro flow with a persisted "seen" flag.
- **Kinetic Path design system** — Material 3 theme built on bundled Space Grotesk + Inter variable TTFs, Safety Orange `#FF5F1F` accent, glassmorphism overlays via `ThemeExtension<KineticPathTokens>`.
- **NASA EONET hazard overlay** — polled every 5 minutes via `GET /hazards`, rendered as category-specific map pins, slide-down proximity banner that fires when a hazard is within the per-category kilometre buffer of the active route.
- **Admin audit log + stats dashboard** — `/admin/analytics/*` (battery drain, provider health, ETA accuracy, WS lifetimes), `/admin/business/*` (MRR, funnel, churn), audit log reader.
- **Safety** — SOS button, client-side crash detector, server-side stranded + speed detection, full-screen alert sheet.
- **Live link for non-members** — mint a short-lived read-only JWT for a stripped trip snapshot URL.

## Architecture

```
         ┌────────────────────────┐
         │      PackPath app      │
         │  Flutter 3.41.4 iOS/An │
         └───────────┬────────────┘
                     │ HTTPS / WSS
                     ▼
     ┌──────────────────────────────┐
     │      PackPath backend        │
     │  FastAPI 0.115 · Python 3.11 │
     └──┬──────┬──────┬──────┬──────┘
        │      │      │      │
        ▼      ▼      ▼      ▼
   ┌─────┐┌─────┐┌─────┐┌──────────────────────────┐
   │ PG  ││Redis││Live ││ upstream APIs            │
   │ +   ││cache││Kit  ││  - Mapbox (tiles + dir)  │
   │PostGIS│rate ││voice││  - Google / Mappls /    │
   │ + TS ││limit││     ││    HERE / TomTom / OSRM │
   │ DB  ││     ││     ││  - NASA EONET (hazards,  │
   └─────┘└─────┘└─────┘│    15 min cache)         │
                        │  - MSG91 (OTP delivery)  │
                        │  - FCM (push, stubbed)   │
                        └──────────────────────────┘
```

See `docs/ARCHITECTURE.md` for the C4 levels, data flow diagrams, and security model.

## Repo layout

```
apps/backend    FastAPI service, Alembic migrations, pytest suite
apps/mobile     Flutter app (iOS + Android + web scaffold)
docs            Architecture, roadmap, session findings, PRD
infra           docker-compose for local Postgres + Redis
designs         Stitch mockups + Kinetic Path design system spec
.github         CI workflow (Flutter 3.41.4 pinned)
```

## Local development

This README intentionally does not duplicate the per-package setup. See:

- [`apps/backend/README.md`](apps/backend/README.md) — FastAPI app, routers, env vars, pytest suite, local run instructions
- [`apps/mobile/README.md`](apps/mobile/README.md) — Flutter pin, module layout, theme, Mapbox token, pre-commit rules

For the full development story (infra spin-up, environment variables, migrations), start in the backend README and then swing over to the mobile README.

## CI

`.github/workflows/ci.yml` runs three jobs on every PR:

- **backend** — `ruff check app` + FastAPI import smoke test
- **mobile** — `flutter pub get`, `flutter analyze --no-fatal-infos --no-fatal-warnings`, `dart format --output=none --set-exit-if-changed lib`
- **alembic** — Postgres 16 + PostGIS + TimescaleDB up via service container, `alembic upgrade head`

Toolchain pin:

- **Flutter 3.41.4** stable, **Dart 3.11.1** (bundled). CI uses `subosito/flutter-action@v2` with an exact version match.
- **Python 3.11**, ruff pinned via requirements.
- **`dart format` is enforced** — if you commit a `.dart` file without running `dart format lib` first, the mobile job will fail.
- **`flutter analyze` is non-blocking on infos and warnings** — only hard errors fail the build. Infos land in the CI step summary for visible backlog without blocking PRs.
- **Pytest suite for backend exists but is run locally** — `pytest apps/backend/tests -q` works with pytest + pytest-asyncio + respx + fakeredis installed. CI does not currently run it; a Session 4 task will add `requirements-dev.txt` and a pytest job to the workflow.

## Docs

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — technical design
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — session-by-session delivery log
- [`docs/PRD.md`](docs/PRD.md) — product requirements
- [`docs/PLAN_v1.1.md`](docs/PLAN_v1.1.md) — v1.1 advanced-features bundle spec
- [`docs/SESSION2_FINDINGS.md`](docs/SESSION2_FINDINGS.md) — Session 2 code smells (all resolved in PR #5, kept for history)
- [`designs/DESIGN_SYSTEM.md`](designs/DESIGN_SYSTEM.md), [`designs/DESIGN_TOKENS.md`](designs/DESIGN_TOKENS.md) — Kinetic Path brand

## License

Proprietary — all rights reserved.

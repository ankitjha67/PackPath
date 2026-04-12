# 09 — Gap analysis: 14 v1 must-have features

Per `docs/PRD.md` §5 and `designs/README.md` Phase 1.

## Legend

- ✅ done
- 🟡 partial
- ❌ missing
- Design = matches the locked Stitch mockup + Kinetic Path

| # | Feature (PRD) | Backend | Mobile logic | Mobile design |
|---|---|---|---|---|
| 1 | Phone OTP login | ✅ `/auth/otp/{request,verify,refresh}` | ✅ `features/auth/otp_screen.dart` + `auth_repository.dart` | ❌ generic Material |
| 2 | Privacy permissions onboarding | n/a | ❌ no screen (privacy *dashboard* exists, not the onboarding intro) | ❌ |
| 3 | Pack lobby (trip list) | ✅ `GET /trips` | ✅ `features/trips/trip_list_screen.dart` with active/past tabs | ❌ generic |
| 4 | Detailed pack lobby (trip detail) | ✅ `GET /trips/{id}` + members | 🟡 covered by `share_trip_screen` (QR + code) — no rich detail screen | ❌ |
| 5 | Invite pack members (QR + code) | ✅ `join_code` + `POST /trips/join` | ✅ `features/trips/share_trip_screen.dart` (qr_flutter) | ❌ generic |
| 6 | Live group map (radar view) ⭐ | ✅ WS `/ws/trips/{id}` + Redis fan-out + `_INSERT_LOCATION` to hypertable | ✅ `features/trips/trip_map_screen.dart` + `live_trip_controller.dart` + `location_service.dart` | ❌ generic — has the affordances but Material defaults |
| 7 | Shared route + ETA | ✅ `POST /trips/{id}/directions` (multi-provider) + `GET /trips/{id}/etas` | ✅ polyline render + `eta_panel.dart` bottom sheet | ❌ |
| 8 | Waypoint manager | ✅ `GET/POST/DELETE /trips/{id}/waypoints` (no reorder) | 🟡 long-press to add + `waypoints_drawer.dart` (bottom sheet, not full screen) | ❌ |
| 9 | In-app group chat | ✅ `GET/POST /trips/{id}/messages` + WS `message` frames + persistence | ✅ `features/chat/chat_screen.dart` + REST history + WS live + typing | ❌ generic |
| 10 | Push-to-talk voice | ✅ `POST /trips/{id}/voice/token` (LiveKit JWT, multi-channel) | 🟡 `features/voice/{voice_service,ptt_button}.dart` exists but only as a FAB on the trip map; no full `pack_voice_comms` screen | ❌ |
| 11 | Trip planning (templates, ready-check, sub-groups) | ✅ `GET /trip_templates`, `POST /trips/{id}/ready_check`, `POST /trips/{id}/subgroups` | ❌ no mobile UI for templates / ready-check / sub-groups | ❌ |
| 12 | Offline maps | ✅ tiles served via Mapbox proxy | 🟡 `tile_cache.dart` + `prefetchBbox` works, but it's a menu action inside the trip map, not a dedicated `offline_maps` screen | ❌ |
| 13 | Trip recap | ✅ `GET /trips/{id}/recap` | ✅ `features/recap/recap_screen.dart` | ❌ generic |
| 14 | Profile / settings | ✅ `GET/PATCH /me` + `GET /me/stats` + `GET /me/audit` | ❌ no profile screen — only `personal_stats_screen` and `audit_log_screen` | ❌ |

## Numbers

- **Backend complete:** 14 / 14 features have backend coverage (some with stubs, e.g. billing).
- **Mobile logic complete:** 8 / 14 features fully implemented, 5 / 14 partial, 1 / 14 missing.
- **Mobile design correct:** 0 / 14.

## Critical gaps (mobile)

These are missing or partial-on-mobile features that BLOCK an honest v1 launch:

1. **Onboarding screen** — first-launch flow; the very first thing the user sees. Currently the app drops you straight onto a phone-input screen.
2. **Privacy permissions intro** — separate from the privacy dashboard; this is the "we need location, here's why" intro that gates the runtime permission request.
3. **Detailed pack lobby** — rich trip-detail screen with members, route preview, status. Today the trip-detail flow is split between `share_trip_screen` and `trip_map_screen` with no roster view.
4. **Full-screen waypoint manager** — currently only a `DraggableScrollableSheet`. The Stitch design is a full screen with reordering UX.
5. **Full-screen voice comms** — currently only a button widget. Stitch has a full screen with active speakers, push-to-talk affordance, channel switcher.
6. **Dedicated offline maps screen** — currently a menu action with a progress bar overlay. Stitch has a screen for region browsing + storage management.
7. **Profile / settings screen** — there is literally no screen named "profile" or "settings". Account management, ghost mode toggle, plan, sign-out — all currently scattered across menu items.

## Cross-cutting design gap

Even the 8 features that are "fully implemented" use the generic blue Material 3 theme. **Restyling all 14 to Kinetic Path is a separate workstream** from filling the 7 missing screens above. Both must happen before v1 ships.

# 06 — Mobile screen → Stitch design mapping

`designs/` has 37 folders. `designs/README.md` carves them into 14 v1 screens (Phase 1), 11 v1.1 screens (Phase 2), 12 v2 screens (Phase 3).

The mapping below covers Phase 1 (v1 must-haves) only. Phase 2/3 are out of scope until v1 ships.

## Phase 1 — v1 must-have (14 screens)

| # | Stitch folder | Spec'd Flutter file | Exists? | Current closest file | Matches design? |
|---|---|---|---|---|---|
| 01 | `onboarding` | `features/onboarding/onboarding_screen.dart` | ❌ no folder | none | n/a |
| 02 | `secure_login_otp` | `features/auth/otp_screen.dart` | ✅ exists | `features/auth/otp_screen.dart` | ❌ generic Material |
| 03 | `privacy_permissions` | `features/onboarding/permissions_screen.dart` | ❌ no folder | `features/privacy/privacy_screen.dart` (different intent — dashboard, not onboarding) | n/a |
| 04 | `pack_lobby` | `features/trips/trip_lobby_screen.dart` | ❌ wrong name | `features/trips/trip_list_screen.dart` covers some of it | ❌ generic |
| 05 | `detailed_pack_lobby` | `features/trips/trip_details_screen.dart` | ❌ no file | none — `share_trip_screen.dart` is closest | ❌ |
| 06 | `invite_pack_members` | `features/trips/invite_screen.dart` | ❌ wrong name | `features/trips/share_trip_screen.dart` | ❌ generic |
| 07 | `the_radar_map_view` ⭐ core | `features/map/live_map_screen.dart` | ❌ wrong location | `features/trips/trip_map_screen.dart` | ❌ heavily generic — has all the affordances but Material defaults |
| 08 | `radar_with_route_details` | `features/map/route_map_screen.dart` | ❌ no file | the same `trip_map_screen.dart` covers it via the ETA panel + route polyline | ❌ |
| 09 | `waypoint_manager` | `features/trips/waypoint_manager_screen.dart` | ❌ wrong name | `features/trips/waypoints_drawer.dart` (bottom sheet, not full screen) | ❌ |
| 10 | `pack_chat` | `features/chat/pack_chat_screen.dart` | ❌ wrong name | `features/chat/chat_screen.dart` | ❌ generic |
| 11 | `pack_voice_comms` | `features/voice/voice_ptt_screen.dart` | ❌ wrong name | `features/voice/ptt_button.dart` (button widget, not a screen) | ❌ — no full screen |
| 12 | `offline_maps` | `features/map/offline_maps_screen.dart` | ❌ no file | offline tiles live as a menu action inside `trip_map_screen.dart`, not a screen | ❌ |
| 13 | `trip_recap_card` | `features/trips/trip_recap_screen.dart` | ❌ wrong name | `features/recap/recap_screen.dart` | ❌ generic |
| 14 | `profile_settings` | `features/profile/profile_screen.dart` | ❌ no folder | none — `me` route shows raw API output via PATCH | ❌ |

## Score

- **0/14** v1 screens exist with the spec'd path.
- **9/14** v1 features have *some* implementation under a different name/structure (login, trip list, share, trip map with ETA + waypoints + offline + chat menu, chat, recap).
- **5/14** v1 screens have no implementation at all (onboarding, permissions onboarding, detailed lobby, full-screen waypoint manager, full-screen voice comms, full-screen offline maps screen, profile settings).
- **14/14** screens fail to match the Stitch design (the existing screens use the generic blue Material 3 theme, not Kinetic Path).

## What this means for the next session

Two distinct piles of work:

1. **Restyle pile** — for the 9 features that exist as Flutter screens (just under different names), restyle to match Stitch + Kinetic Path. May involve renaming + relocating files to match `designs/README.md` paths so the convention is honored.
2. **Build pile** — for the 5 screens that don't exist at all, build from scratch using the new theme.

Both piles should follow the same workflow: read the matching `code.html` for layout intent, look at the `screen.png` for visual target, implement idiomatically in Flutter using the new `lib/core/theme/` package.

## Phase 2 / Phase 3 screens

Untouched in this audit. The v1.1 backend (safety, expenses, livelink, etc.) ships endpoints that the Phase 2 screens (`mission_briefing`, `gear_checklist`, `fuel_toll_planner`, etc.) would consume — but per `designs/README.md` these are explicitly out of v1 scope and shouldn't be pulled forward without approval.

# PackPath — Stitch Design Mockups

This folder contains the Stitch-generated design mockups for PackPath. Every Flutter screen in `apps/mobile/lib/features/` must match the corresponding mockup here.

**Total screens:** 37
**Design system:** See `../DESIGN_SYSTEM.md` ("Kinetic Path / Precision Utility") — Space Grotesk + Inter, Safety Orange primary, Material 3 tokens, glassmorphism overlays.

## How to use these references

Each folder contains:
- `code.html` — Stitch export using Tailwind + Material Symbols. Use as a **spec for layout intent, design tokens, spacing, and typography** — do NOT port HTML structure verbatim into Flutter.
- `screen.png` — Visual source of truth. Match this in the final Flutter implementation.

**Workflow for implementing any screen:**
1. Read the corresponding `code.html` to extract layout, tokens, and component structure.
2. Look at `screen.png` as the visual target.
3. Implement idiomatically in Flutter using Material 3 widgets (not nested `Container` dumps).
4. Pull all colors, typography, and spacing from `apps/mobile/lib/core/theme/app_theme.dart` — never hardcode.
5. Apply the `anti-slop-design` skill bar: real imagery where relevant, crafted icons (Material Symbols), distinctive typography, zero emoji-as-icon.

## Before building ANY screen

Claude Code must first:
1. Read `../DESIGN_SYSTEM.md` in full.
2. Parse the Tailwind config blocks from several HTML files (`onboarding`, `the_radar_map_view`, `pack_lobby`) to extract the full color palette, type scale, and spacing scale.
3. Generate `designs/DESIGN_TOKENS.md` consolidating every token.
4. Generate `apps/mobile/lib/core/theme/app_theme.dart` — `ThemeData` with Material 3 color scheme, text theme, and custom extensions for the Kinetic Path tokens.
5. Generate `apps/mobile/lib/core/theme/app_colors.dart`, `app_typography.dart`, `app_spacing.dart` as the source of truth.
6. Only then start building screens.

## Phased screen mapping

Stitch generated a full v1+v2+v3 app. Not everything ships in the 6-weekend MVP. Phases below are **locked** — do not pull v2/v3 screens into v1 without explicit approval.

### Phase 1 — v1 MVP (weekends 1–6, ship to Play Store + App Store)

These 13 screens are the **non-negotiable v1 scope**. Every feature we committed to (live group map, shared route+ETA, chat, PTT voice, trip planning, offline maps) maps to these.

| # | Screen folder | Flutter widget | Weekend |
|---|---|---|---|
| 01 | `onboarding` | `features/onboarding/onboarding_screen.dart` | W1 |
| 02 | `secure_login_otp` | `features/auth/otp_screen.dart` | W1 |
| 03 | `privacy_permissions` | `features/onboarding/permissions_screen.dart` | W1 |
| 04 | `pack_lobby` | `features/trips/trip_lobby_screen.dart` | W1 |
| 05 | `detailed_pack_lobby` | `features/trips/trip_details_screen.dart` | W1 |
| 06 | `invite_pack_members` | `features/trips/invite_screen.dart` (QR + 6-digit code) | W1 |
| 07 | `the_radar_map_view` | `features/map/live_map_screen.dart` ⭐ **core screen** | W2 |
| 08 | `radar_with_route_details` | `features/map/route_map_screen.dart` | W3 |
| 09 | `waypoint_manager` | `features/trips/waypoint_manager_screen.dart` | W3 |
| 10 | `pack_chat` | `features/chat/pack_chat_screen.dart` | W4 |
| 11 | `pack_voice_comms` | `features/voice/voice_ptt_screen.dart` | W5 |
| 12 | `offline_maps` | `features/map/offline_maps_screen.dart` | W5 |
| 13 | `trip_recap_card` | `features/trips/trip_recap_screen.dart` | W6 |
| 14 | `profile_settings` | `features/profile/profile_screen.dart` | W6 |

### Phase 2 — v1.1 / v1.2 (post-launch, first 2 months after ship)

Features that deepen engagement and justify the premium tier but aren't blocking the initial launch.

| Screen folder | Purpose |
|---|---|
| `mission_briefing` | Pre-trip group kickoff screen — surfaces ETA, weather, roles |
| `personal_navigator_card` | Per-user HUD card shown to each member |
| `live_telemetry_hud` | Speed, heading, next waypoint — overlaid on map |
| `comms_offline_hud` | Graceful degradation when connection drops |
| `trip_history` | Past trips list with stats |
| `weather_hazards` | Weather overlay on live map |
| `atmospheric_intelligence` | Extended weather briefing screen |
| `member_readiness_checklist` | Pre-trip per-member check (fuel, gear, location permission granted) |
| `gear_checklist` | Trip-level gear list, shareable |
| `fuel_toll_planner` | Fuel stop + toll cost estimation along route |
| `community_landmarks` | User-submitted POIs along popular routes |

### Phase 3 — v2 (premium tier + advanced features)

Screens that target the "Marshall" persona (trip leader / group admin) and SOS safety — these justify the paid tier and differentiate PackPath from Life360.

| Screen folder | Purpose |
|---|---|
| `marshall_command` | Trip leader control center — reroute all, broadcast, recall |
| `marshall_readiness_monitor` | Leader view of every member's readiness |
| `tactical_radar_overlay` | Advanced radar with zones, hazards, tactical markers |
| `expedition_analytics` | Trip-level analytics dashboard |
| `expedition_logistics` | Multi-leg trip logistics planner |
| `expedition_summary` | Post-expedition report (richer than trip_recap_card) |
| `advanced_analytics_hub` | Cross-trip analytics for power users |
| `vehicle_diagnostics` | OBD-II integration for supported vehicles |
| `safety_health_monitor` | Biometric/health monitoring (wearable integration) |
| `sos_trigger_flow` | SOS activation flow |
| `sos_active_radar_view` | Live SOS state on radar |
| `sos_emergency_dashboard` | Emergency dashboard with contacts, location broadcast |

## Design tokens to extract (Phase 0 — before coding)

From `code.html` files, extract and document in `DESIGN_TOKENS.md`:

**Colors (Material 3 scheme):**
- Primary: `#ab3600` (Safety Orange) + container `#ff5f1f`
- Secondary: `#2559bd` (Pathfinder Blue)
- Tertiary: `#006493`
- Surface hierarchy: `surface`, `surface-container-lowest/low/high/highest`, `surface-dim`, `surface-bright`
- Semantic: `error` `#ba1a1a`, `error-container` `#ffdad6`
- Full dark mode palette (extract from HTML with `.dark` class)

**Typography:**
- Display / Headline: **Space Grotesk** (300–700)
- Title / Body / Label: **Inter** (300–700)
- Scale: `display-lg/md/sm`, `headline-lg/md/sm`, `title-lg/md/sm`, `body-lg/md/sm`, `label-lg/md/sm`

**Spacing:**
- Extract Tailwind spacing classes actually used (likely 4/8/12/16/24/32/48/64)

**Radii, elevation, glassmorphism:**
- Overlay rule: `surface-container-lowest` with 12px `backdrop-blur` + 85% opacity
- CTA gradient: `primary` → `primary-container` at 135°

## The "No-Line" Rule

Per `DESIGN_SYSTEM.md`, 1px solid borders are **prohibited** for sectioning. Use background surface shifts instead. This is a hard constraint — flag any Flutter PR that introduces border dividers.

## Cross-references

- Full design system doc: `../DESIGN_SYSTEM.md`
- Stitch's original research PRD: `../research_prd.html`
- Project architecture: `../../docs/ARCHITECTURE.md` (to be created)
- Phased roadmap: `../../docs/ROADMAP.md` (to be created)

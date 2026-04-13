# PackPath Mobile

Flutter 3.41.4 (Dart 3.11.1) app for PackPath. Single codebase for iOS, Android, and a web scaffold (useful for fast design iteration; the production surface is the mobile apps).

## Flutter version pin

- **Flutter 3.41.4 stable**, **Dart 3.11.1** (bundled).
- CI pins the exact version via `subosito/flutter-action@v2` in `.github/workflows/ci.yml`. Your local toolchain should match — `fvm` or the archive at <https://docs.flutter.dev/release/archive> both work.
- Required for `Color.withValues(alpha:)` (Session 3 Track 1 swept the whole codebase off deprecated `withOpacity`). Earlier Flutter versions will fail `dart analyze` with "`withValues` undefined".

### Why bundled fonts instead of `google_fonts`

Session 2 dropped the `google_fonts` package and committed the variable TTFs into `fonts/`:

- `fonts/Inter-Variable.ttf`
- `fonts/SpaceGrotesk-Variable.ttf`

`google_fonts` 6.x pulls TTFs from Google Fonts CDN at runtime. That's a network round-trip on every cold start, a privacy foot-gun, and a runtime failure point in airplane mode / dead-zone trips — which is exactly the use case PackPath is built for. The 6.x release also had an API incompatibility with our Flutter pin at the time, and bundling in-tree removed both problems in one move. Both typefaces are SIL Open Font License; attribution ships alongside the TTFs.

The registration lives in `pubspec.yaml`:

```yaml
fonts:
  - family: SpaceGrotesk
    fonts:
      - asset: fonts/SpaceGrotesk-Variable.ttf
  - family: Inter
    fonts:
      - asset: fonts/Inter-Variable.ttf
```

## Module layout

```
lib/
├── main.dart                        app bootstrap
├── app.dart                         MaterialApp.router + KineticPath theme
├── config/
│   ├── env.example.dart             template — copy to env.dart
│   ├── env.dart                     (gitignored) apiBaseUrl + mapboxPublicToken
│   ├── theme.dart                   theme wiring
│   └── firebase_options.dart        stub (silent-fallback init)
├── core/
│   ├── api_client.dart              Dio + bearer-token interceptor
│   ├── token_storage.dart           JWT persistence (secure storage)
│   ├── ws_client.dart               /ws/trips/{id} channel
│   └── theme/                       Kinetic Path design system tokens
│       ├── app_theme.dart           ThemeData builder (light + dark)
│       ├── app_colors.dart          Material 3 ColorScheme anchors
│       ├── app_typography.dart      SpaceGrotesk + Inter text theme
│       ├── app_radii.dart           BorderRadius scale
│       ├── app_spacing.dart         spacing scale (4/8/12/16/24/32/48/64 dp)
│       └── kinetic_path_tokens.dart ThemeExtension: ctaGradient,
│                                    glassmorphismDecoration, floatingShadow
├── features/
│   ├── analytics/                   EventLogger + Hive buffer for /events
│   ├── audit/                       admin audit log viewer
│   ├── auth/                        phone OTP screens + providers
│   ├── billing/                     plans / subscription screen (stub)
│   ├── chat/                        REST history + WS live frames
│   ├── expenses/                    expenses + balances
│   ├── hazards/                     NASA EONET integration:
│   │   ├── hazard_model.dart            HazardDto + GeometryDto (Point/Polygon)
│   │   ├── hazards_repository.dart      Dio + tripHazardsProvider (5 min poll)
│   │   ├── hazard_layer.dart            MarkerLayer + tap-to-open details sheet
│   │   ├── hazard_proximity.dart        per-category km buffer proximity check
│   │   └── hazard_banner.dart           slide-down alert with expandable list
│   ├── map/                         live_trip_controller, location service,
│   │                                tile cache, map providers
│   ├── onboarding/                  3-pillar Kinetic Path intro screen
│   ├── privacy/                     privacy dashboard screen
│   ├── push/                        FCM init + device register (stubbed)
│   ├── recap/                       post-trip stats wrapped-style screen
│   ├── safety/                      SOS button, crash detector, alert sheet
│   ├── stats/                       personal stats screen
│   ├── trips/                       list, create, join, detail, map,
│   │                                waypoints drawer, ETA panel
│   └── voice/                       LiveKit voice service + PttButton
├── routing/
│   └── router.dart                  go_router config
└── shared/
    ├── models/                      DTOs (WaypointDto, TripDto, HazardDto, …)
    └── widgets/                     shared primitives

fonts/
├── Inter-Variable.ttf               bundled (Session 2)
└── SpaceGrotesk-Variable.ttf        bundled (Session 2)
```

## Running locally

```bash
flutter pub get
cp lib/config/env.example.dart lib/config/env.dart
# edit env.dart: Env.apiBaseUrl + Env.mapboxPublicToken
flutter run -d <device>
```

To point at a local backend instead of staging, either edit `lib/config/env.dart` directly or pass `--dart-define`:

```bash
flutter run -d <device> --dart-define=API_BASE_URL=http://localhost:8000
```

Emulator-to-host URLs:

- **Android emulator** → `http://10.0.2.2:8000`
- **iOS simulator / macOS host** → `http://localhost:8000`
- **Physical device** → your machine's LAN IP, e.g. `http://192.168.1.42:8000`
- **Staging** → whatever your deployed backend URL is

Local web scaffold for fast design iteration (not the production surface):

```bash
flutter run -d chrome
```

## Mapbox token

- Sign up at <https://mapbox.com> and create a public token (`pk....`).
- Set it in `lib/config/env.dart` as `Env.mapboxPublicToken`, or pass `--dart-define=MAPBOX_ACCESS_TOKEN=pk....`.
- Without it, the map layer falls back to OSM tiles — still functional, just less pretty.
- The client uses it only for the tile layer. **All routing goes through the backend's `/trips/{id}/directions` proxy**, which uses the server-side `MAPBOX_SERVER_TOKEN` — your public token is never used for routing and the server token never touches the device.
- `GET /maps/providers` on the backend tells you what providers the server has keys for, so the in-app tile picker only shows what's actually configured.

## Windows / cross-drive Kotlin cache gotcha

If your repo lives on a different drive than `~/.gradle` / `$GRADLE_USER_HOME`, Kotlin's incremental compilation cache races on cross-drive paths and the Android build dies with `InvalidPathException`. The workaround is already in-tree:

```properties
# apps/mobile/android/gradle.properties:4
kotlin.incremental=false
```

This disables incremental Kotlin compile at the cost of slower first builds. Revisit when Kotlin fixes the cross-drive bug.

## Kinetic Path design system

Design tokens live in `lib/core/theme/`. The narrative lives in `designs/DESIGN_SYSTEM.md` and `designs/DESIGN_TOKENS.md`. The short version:

- **Primary color**: Safety Orange `#FF5F1F` — drives `colorScheme.primary`, CTA gradients, route polylines, hazard icons, active ring on member markers.
- **Glassmorphism** via `Theme.of(context).extension<KineticPathTokens>()!.glassmorphismDecoration()` — the HUD cards, ETA panel, app bar, and hazard banner all use it.
- **Typography**: SpaceGrotesk for display, Inter for body.
- **Radii**: `AppRadii.xs/lg/xl/full/round`. Standard container rounding is `AppRadii.xl` (8 dp).
- **Spacing**: `AppSpacing.xs/sm/md/base/lg/xl/xxl/xxxl` — 4/8/12/16/24/32/48/64 dp.
- **Shadows**: `tokens.floatingShadow` — never `Colors.black26`, always tinted onSurface @ 6 %.
- **Reference implementation**: `lib/features/onboarding/onboarding_screen.dart` is the canonical "how to use the theme" example.

## Pre-commit discipline

CI runs both on every PR, and the format check is **enforced**:

```bash
dart format lib                                       # auto-format before commit
dart format --output=none --set-exit-if-changed lib   # CI check (must exit 0)
flutter analyze --no-fatal-infos --no-fatal-warnings  # CI check (errors only)
```

If you commit a `.dart` file you haven't run `dart format` on, the mobile job will fail. The analyzer is configured to only fail on hard errors; infos and warnings surface in the CI step summary so the backlog is visible without blocking PRs.

Current baseline (post-Session 3): **11 infos, 0 warnings, 0 errors**. The 11 infos are trailing-comma nits, pre-existing `use_build_context_synchronously` checks in `trip_map_screen.dart`, one `WillPopScope` deprecation in `safety_alert_sheet.dart`, and one `roomOptions` deprecation in `voice_service.dart`. None block CI.

## Feature flags + known gaps

- **Push notifications** — Firebase config files (`android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`, `lib/config/firebase_options.dart`) are stubs with dummy values. `lib/features/push/push_service.dart` initializes Firebase inside a try/catch that silently no-ops when the project is unconfigured. FCM push is disabled until Session 4 wires a real project via `flutterfire configure`.
- **Dev-mode skip-auth** — the router honours a dev-only escape hatch that bypasses OTP verification. It is a backlog item to remove before any store listing.
- **Widget test coverage** — a placeholder `test/widget_test.dart` exists. Real coverage is a Session 4 quality task.

# 01 — Executive summary

## Top findings (most critical first)

- **🔴 Mobile cannot build at all.** `apps/mobile/android/` is missing `build.gradle`, `settings.gradle`, gradle wrapper, and `MainActivity.kt`. `apps/mobile/ios/` is missing `Runner.xcodeproj`, `AppDelegate.swift`, `Podfile`. Only the manifests exist. `flutter build apk` would fail. **No v1 ship is possible until `flutter create .` is run.**
- **🔴 Mobile theme is design-system-naked.** `lib/config/theme.dart` is 21 lines using a generic blue seed `#3B82F6`. Zero relationship to Kinetic Path: no Safety Orange `#ab3600`, no Pathfinder Blue `#2559bd`, no Space Grotesk + Inter, no glassmorphism extension, no spacing/radius scale. Every existing screen will need restyling once the new theme lands.
- **🔴 Zero rate limiting on auth.** `/auth/otp/request` accepts unlimited POSTs per phone or per IP. SMS-bombing attack vector + cost vector when MSG91 is wired.
- **🟠 JWT secret defaults to `change-me-in-prod`** — if `JWT_SECRET` is unset in prod, anyone can mint tokens. No production startup check guards this.
- **🟠 Admin analytics + business endpoints only require `current_user`** — any logged-in user can read battery_drain, MRR, churn, etc. No `is_admin` flag exists.
- **🟠 Battery-suspend code is dead.** `AdaptiveLocationService.onBatteryUpdate(<15%)` shuts the stream down but **no caller ever invokes it**, and even if invoked it never restarts when battery recovers.
- **🟡 13 of 14 v1 Stitch screens have no matching Flutter file** with the right name (the existing screens roughly cover the *features* but not the named v1 routes from `designs/README.md`).
- **🟡 Mobile CI on PR #3 was failing on `flutter analyze`** in the last visible run before merge. Backend lint + alembic green. Cause not yet diagnosed (logs needed auth).
- **🟢 Backend is solid.** 62 routes register cleanly, 2 Alembic migrations apply against TimescaleDB, WebSocket fan-out via Redis pub/sub is real, JWT auth is enforced on every protected route.
- **🟢 Designs are complete.** 37 Stitch folders + `DESIGN_SYSTEM.md` are on disk. Locked spec. Kinetic Path is the source of truth.

# PackPath — Session Handoff (on-device testing)

**Purpose:** everything a fresh session (human or AI) needs to pick up where the
last one stopped: the app now **builds and runs on a physical Android device**,
a full code-level bug sweep has landed, and what remains is **on-device
walk-through testing + fixing anything that misbehaves at runtime**.

Last updated after commit `1eb6c95`.

---

## 1. Current state (TL;DR)

- **Repo:** `ankitjha67/PackPath` — mobile app in `apps/mobile` (Flutter), backend in `apps/backend` (FastAPI).
- **Work branch:** `claude/reconcile-flutter-3-41-4-oFeAR` — **do all work here; push only here.**
- **Toolchain:** Flutter **3.41.4** / Dart 3.11, AGP 8.11.1, Gradle 8.14, Kotlin 2.2.20, JDK 21.
- **Status:** ✅ builds, installs, and launches on a OnePlus LE2111 (Android 14, device id `e3b9507e`). `flutter analyze` = **0 issues**, `flutter test` passes, CI green.
- **What's left:** exercise every feature on the device per `docs/ON_DEVICE_TESTING.md` and fix runtime bugs as they appear.

## 2. Get the code

Existing local clone (most likely — reuse it):
```powershell
cd <your>\PackPath
git checkout claude/reconcile-flutter-3-41-4-oFeAR
git pull
```
Fresh clone:
```powershell
git clone https://github.com/ankitjha67/PackPath.git
cd PackPath
git checkout claude/reconcile-flutter-3-41-4-oFeAR
```

## 3. Build & run on the device

```powershell
cd <your>\PackPath\apps\mobile
flutter pub get
$env:GRADLE_OPTS = "-Djava.net.preferIPv4Stack=true"   # avoids IPv6 Gradle download timeouts
flutter run -d e3b9507e
```
Notes:
- Only **one** Gradle build at a time (a second concurrent build corrupted the cache before). To stop a run, press `q` in the Flutter terminal — do **not** `taskkill java` mid-build.
- Hot reload `r` / restart `R` for Dart changes. **Native/plugin/manifest changes (e.g. anything under `android/`, adding a package) need a full stop + `flutter run`.**
- Harmless log noise on this device: `qdgralloc` / `AdrenoUtils` / `Gralloc4` / `OpenGLRenderer` / `callGcSupression`, and Gradle/AGP/Kotlin "support will be dropped" warnings. Ignore them.

## 4. ⚠️ Backend must be reachable from the phone (the #1 gotcha)

A physical phone cannot reach `localhost`/`10.0.2.2` (that's emulator-only). If this isn't set up, **"Send OTP" spins and everything after login looks dead** — it is *not* an app bug.

1. Run the backend bound to all interfaces (Postgres + Redis up):
   ```powershell
   cd apps\backend
   .\.venv\Scripts\uvicorn.exe app.main:app --host 0.0.0.0 --port 8000 --reload
   ```
2. Find the PC's LAN IP: `ipconfig` → e.g. `192.168.1.23`.
3. Edit **`apps/mobile/lib/config/env.dart`** (gitignored — safe to edit locally):
   ```dart
   static const String apiBaseUrl = 'http://192.168.1.23:8000';
   static const String wsBaseUrl  = 'ws://192.168.1.23:8000';
   ```
4. Allow port 8000 through Windows Firewall (Private), then confirm from the **phone's browser**: `http://192.168.1.23:8000/healthz` → `{"status":"ok"}`.

Cleartext `http`/`ws` is already allowed for **debug** builds (`android/app/src/main/.../debug/AndroidManifest.xml`), so no manifest change is needed.

## 5. Hard constraint on "who taps the phone"

A **cloud** session cannot reach a USB/adb device — it can read/edit/build/push code but cannot see the phone's screen or tap it. So on-device testing is **collaborative**: the device operator runs the app and reports what happens; the coding session fixes and pushes; operator does `git pull` + hot-reload/`R` (or a full rebuild for native changes). If this new session runs **locally on the machine the phone is plugged into**, it can drive `flutter`/`adb` directly.

## 6. What to test (and specifically what to verify)

Walk `docs/ON_DEVICE_TESTING.md` top to bottom. Recently fixed items worth confirming on the device:

- **Onboarding/Auth (§1):** Get Started / Sign In reach Login (router bounce fixed); OTP → Trips; kill/reopen skips login.
- **Trips (§2):** create/join opens the map **and system Back returns to the trips list** (back-stack fix).
- **Live/Ghost/Privacy (§3):** ghost mode persists across re-entering the map (reads server state); member **battery ring** now appears.
- **Chat (§4):** send appears once; leave+reopen chat keeps history (no vanish, no dupes); offline banner + queue.
- **Bluetooth mesh (§5, needs TWO phones):** newest/riskiest; verify the "messaging N nearby over Bluetooth" banner and that a message crosses in airplane mode.
- **Voice PTT (§6):** hold-to-talk; leaving the map releases the mic/room; quick taps don't leave the mic stuck on.
- **Expenses (§7):** the amount field now offers a **decimal point**; `99.50` is accepted and shows as ₹99.50 (not ₹100); balances use 2 decimals.
- **Safety (§8):** crash spike → 10s countdown → alert; **offline SOS/crash now say "queued"** and deliver on reconnect (no more false "sent").
- **Hazards/Recap/Profile/Billing (§9):** load for current user. **Billing "Upgrade" is an intentional stub** (shows a "coming soon" snackbar) — not a bug.

## 7. Git workflow + a recurring snag

- Branch: `claude/reconcile-flutter-3-41-4-oFeAR`. Never push elsewhere without asking.
- **`git pull` keeps aborting on local changes to generated files** (`pubspec.lock`, sometimes `android/gradle.properties`). These are regenerated, safe to discard. From `apps/mobile`:
  ```powershell
  git checkout -- pubspec.lock
  git pull
  flutter pub get
  ```
- Commit message trailer used in this project:
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01QRHUE7YQ7SYFG8ptRv1AsG
  ```
  (A new session should use its own session link.)

## 8. Vendored dependency note

`flutter_nearby_connections` 1.1.2 (Bluetooth mesh) is **abandoned** and references Flutter's removed v1 Android embedding (`PluginRegistry.Registrar`), so it won't compile on 3.41. It's **vendored + patched** at `apps/mobile/third_party/flutter_nearby_connections` and wired via a `dependency_overrides: path:` in `apps/mobile/pubspec.yaml`. Only change: the dead `registerWith` removed from `FlutterNearbyConnectionsPlugin.kt`. `third_party/**` is excluded from the analyzer.

## 9. What was accomplished leading here (newest first)

- `1eb6c95` runtime bug sweep: offline SOS/crash queue, voice room/mic leak + stuck-mic, chat re-entry/dedup, ghost-mode-from-server, WS-ready gating, battery telemetry, mesh leak, create/join back-stack, expense decimals, analyzer clean.
- `3f051b7` routing: onboarding → login bounce fixed.
- `cd76bdb` onboarding overflow fix.
- `2ec79ed` vendor + patch `flutter_nearby_connections`.
- `9263911`/`6f62d2f` align Java/Kotlin JVM target to 17 (plugin compile).
- `de48741` inject namespace for plugins missing it (AGP 8).
- `19c8ea9`/`e433950` Gradle `-bin` dist + IPv4 (download reliability).
- Earlier: Flutter 3.41 reconcile, backend security/correctness audit fixes, N+1 batching, Bluetooth mesh chat feature, voice per-trip scoping.

## 10. Suggested next action for the new session

1. `git pull` on the work branch; `flutter pub get`.
2. Set `env.dart` LAN IP + start the backend on `0.0.0.0`; confirm `/healthz` from the phone.
3. `flutter run -d e3b9507e`.
4. Walk `docs/ON_DEVICE_TESTING.md` §1→§9; for each failure capture the red stack trace / `adb logcat` and the step number, fix on the branch, push, re-pull, hot-reload.
5. Bluetooth mesh (§5) is the highest-risk area and needs a second phone.

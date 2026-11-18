# PackPath — On-Device Test Checklist (Android)

A step-by-step runbook for exercising every feature on a real Android phone.
Work top to bottom. For each step: do the action, compare to **Expect**, and if
it doesn't match, grab the error (see [Capturing errors](#capturing-errors)) and
report it.

> This cannot be run from a cloud sandbox (no USB, no adb reach to your phone).
> Run it on the machine the phone is plugged into.

---

## 0. Prerequisites (one-time)

### 0.1 Device
- Enable **Developer options** → **USB debugging** on the phone, plug in, accept
  the "Allow USB debugging?" prompt.
- Confirm it's seen:
  ```bash
  flutter devices
  ```
  **Expect:** your phone listed with an id (e.g. `RZ8…  • android-arm64`).

### 0.2 Backend reachable from the phone
A physical phone can't reach `localhost` on your PC — use your PC's LAN IP.
- Find your PC IPv4: `ipconfig` (Windows) → e.g. `192.168.1.23`.
- Start the backend bound to all interfaces, with the DB up:
  ```bash
  cd apps/backend
  (cd ../../infra && docker compose up -d)          # Postgres + Redis
  .\.venv\Scripts\uvicorn.exe app.main:app --host 0.0.0.0 --port 8000 --reload
  ```
- Allow port 8000 through the Windows firewall (first run prompts; allow Private).
- Sanity check from the **phone's** browser: `http://192.168.1.23:8000/healthz`
  → `{"status":"ok"}`. If that fails, nothing below will work — fix networking first.

### 0.3 Point the app at the backend
Edit `apps/mobile/lib/config/env.dart`:
```dart
static const String apiBaseUrl = 'http://192.168.1.23:8000';   // your PC IP
static const String wsBaseUrl  = 'ws://192.168.1.23:8000';
```
(CORS doesn't apply to the native app, so no allowlist needed. `env.dart` is
gitignored — safe to edit locally.)

### 0.4 Build + install + launch
```bash
cd apps/mobile
git pull                      # includes the AGP-8 namespace fix (required to build)
flutter pub get
flutter run -d <device-id>
```
**Expect:** app compiles, installs, launches to the **onboarding** screen (first
run) or **login**. Keep this terminal open — it streams logs and gives hot reload
(`r` = reload, `R` = restart, `q` = quit).

> First Android build downloads Gradle deps — fine on a normal network.

---

## 1. Onboarding + Auth

| # | Action | Expect |
|---|--------|--------|
|1.1| First launch | 3-pillar onboarding; "Get started" → `/login` |
|1.2| Enter phone, tap **Send OTP** | advances to OTP screen; **no** connection-timeout error (if timeout → backend/IP wrong, see 0.2) |
|1.3| OTP screen | in dev mode the code is auto-filled (backend returns `debug_otp`); tap verify | 
|1.4| Verify | lands on **Trips** list; no crash |
|1.5| Kill app, reopen | goes **straight to Trips** (not login) — token persisted in secure storage + router guard |
|1.6| Settings → **Log out** | returns to `/login`; reopen stays logged out |
|1.7| Log in as a **different** phone | Trips/profile show the new account's data only (no leakage from the previous user) |

**Report for this section:** does 1.2 reach the OTP screen, and does 1.5 skip login?

---

## 2. Trips

| # | Action | Expect |
|---|--------|--------|
|2.1| **Create trip** | map screen opens for the new trip; appears in Trips list |
|2.2| Trip map | your location marker appears (grant location permission when asked) |
|2.3| **Share** / join code | a 6-char code is shown |
|2.4| Second device/account → **Join by code** | joins; both members visible |
|2.5| Trip settings → rename / end trip | reflects immediately |

---

## 3. Live location, Ghost mode, Privacy

| # | Action | Expect |
|---|--------|--------|
|3.1| Move the phone (or use a mock location) | your marker updates on the other member's map within a few seconds |
|3.2| Toggle **Ghost mode** on | you disappear from other members' maps and from their ETA list |
|3.3| Ghost off | you reappear |
|3.4| Privacy screen → set visibility "none" / share window | other members stop seeing your location (even without ghost) |

---

## 4. Chat (online)

| # | Action | Expect |
|---|--------|--------|
|4.1| Open trip chat, send a message | appears **once** for you (no duplicate bubble) |
|4.2| Other member | receives it live |
|4.3| Turn **Wi-Fi/data off** briefly, send | shows "Offline — message queued…" snackbar |
|4.4| Turn connectivity back on | queued message sends; chat reconnects automatically (no manual refresh) |

---

## 5. Bluetooth offline mesh chat  ⚠️ needs **two phones**

| # | Action | Expect |
|---|--------|--------|
|5.1| Install on **two** phones, both logged in as members of the **same** trip, both on the chat screen | — |
|5.2| Put **both** in **airplane mode**, then turn **Bluetooth back on** | chat banner: "Offline — looking for nearby members over Bluetooth…" |
|5.3| Grant the Bluetooth/Nearby permission prompts on both | banner → "messaging 1 nearby member over Bluetooth" |
|5.4| Send a message from phone A | appears on phone B within a few seconds, over Bluetooth |
|5.5| Restore connectivity on A | the mesh message reconciles to the server; on a fresh chat open it loads from history, **not duplicated** |

**This is the newest/riskiest feature and can't be exercised in CI — worth the most attention.** Report the banner text and whether 5.4 crosses.

---

## 6. Voice push-to-talk  ⚠️ two phones

| # | Action | Expect |
|---|--------|--------|
|6.1| Tap the PTT button | "connecting…" then "Hold to talk" (needs LiveKit configured on the backend; if not, expect a clean error, not a crash) |
|6.2| Hold → speak → release on A; B holds nothing | B hears A |
|6.3| Leave the trip map screen | mic/room disconnects (voice is scoped per-trip now) |

---

## 7. Expenses

| # | Action | Expect |
|---|--------|--------|
|7.1| Add expense, amount `99.50` | accepted (decimals work now); not silently dropped |
|7.2| Add a few expenses across members | balances compute; "who owes whom" is correct |

---

## 8. Safety / crash detection

| # | Action | Expect |
|---|--------|--------|
|8.1| Trigger SOS | full-screen alert fans out to other members |
|8.2| Simulate a crash spike (shake hard / drop on a cushion) | a **10-second countdown dialog** appears first with "I'm OK" cancel — it does **not** instantly alarm the group |
|8.3| Let the countdown finish | crash alert is sent |

---

## 9. Hazards, Recap, Profile, Billing

| # | Action | Expect |
|---|--------|--------|
|9.1| Map with waypoints | nearby hazards (NASA EONET) render; polling stops when you leave the map |
|9.2| End a trip → Recap | post-trip stats load |
|9.3| Profile / personal stats / audit log | load for the current user |
|9.4| Plans / upgrade | creates a `pending` subscription (no real payment); no Pro actually granted |

---

## Capturing errors

When something misbehaves, grab the detail so it can be fixed:

- **From the `flutter run` terminal:** copy the red stack trace / exception.
- **Logcat (filtered):**
  ```bash
  adb logcat -v time | findstr /i "flutter packpath AndroidRuntime Exception"
  ```
- **A full crash:** `adb logcat -b crash -d > crash.txt` and share `crash.txt`.
- **Network issues:** note whether `http://<PC-IP>:8000/healthz` loads from the
  phone's browser; most "nothing happens on Send OTP" issues are the IP/firewall.

Paste the output and the step number; fixes go out on the branch and you
`git pull` + hot-restart (`R`).

---

## Quick status key
- ✅ works as expected
- ⚠️ works with caveats (note them)
- ❌ broken (attach error + step #)

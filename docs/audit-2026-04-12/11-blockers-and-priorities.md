# 11 — Blockers and priorities

What MUST be fixed before any v1 ship, in order.

## Hard blockers (can't ship at all)

1. **🔴 Run `flutter create .` for Android + iOS scaffolds.** No native projects exist. `flutter build apk` and `flutter build ios` cannot succeed today. This is Task 0 — has to happen before anything else, including the design system extraction. ETA: minutes.

2. **🔴 Set a real package name / bundle identifier.** Default `com.example.packpath` will be rejected by both stores. Should align with `app.packpath.mobile` already used in `userAgentPackageName`.

3. **🔴 Add Firebase config files (`google-services.json`, `GoogleService-Info.plist`) + run FlutterFire CLI to generate `firebase_options.dart`.** Without these, push notifications silently noop and the chat-while-backgrounded UX is broken. Backend FCM hook is ready and waiting.

4. **🔴 Diagnose and fix the mobile CI failure.** It's been failing for 4 commits with no log access. Either pull the artifact, gist the output from inside CI, or rewrite the step to print errors as `::error::` lines so we can read the failure on the public job page.

## Hard blockers (security / safety, can't ship to real users)

5. **🟠 Add rate limiting on `/auth/otp/{request,verify}`.** Pull `slowapi`, apply `5/min/phone` on request and `10/5min/phone` on verify with progressive backoff on failed verifies.

6. **🟠 Add a startup guard against `JWT_SECRET == "change-me-in-prod"` in non-local environments.** One-line `assert` in `lifespan()`.

7. **🟠 Add a startup guard against `OTP_DEV_MODE` in non-local environments.** Otherwise a misconfigured prod deploy returns OTP codes to anyone who asks.

8. **🟠 Gate `/admin/analytics/*` and `/admin/business/*` behind an `is_admin` user flag.** Add the column to the `users` model + a `require_admin` dependency.

## Major UX blockers (would be terrible reviews on day 1)

9. **🔴 Restyle every screen to Kinetic Path.** Today the app uses a generic blue Material 3 theme that has no relationship to the locked Stitch designs. Restyle requires the new theme package first.

10. **🔴 Build the 7 missing v1 screens** identified in `09-gap-analysis.md`:
    - Onboarding intro
    - Privacy permissions intro
    - Detailed pack lobby (rich trip-detail screen)
    - Full-screen waypoint manager (with reorder)
    - Full-screen voice comms screen
    - Dedicated offline maps screen
    - Profile / settings screen

11. **🟠 Fix the dead battery-suspend code in `AdaptiveLocationService`.** Wire `onBatteryUpdate` from the controller layer (or pull `battery_plus`), and add a `resume()` path on charging / battery recovery. Without this, we cannot honestly claim the < 4% drain / hour PRD metric.

## Should-fix before launch (won't kill the launch but will hurt)

12. **🟡 Hash OTP codes in Redis** (HMAC with secret).
13. **🟡 Rotate refresh tokens.** Add a Redis blacklist for used JTIs.
14. **🟡 Lock CORS origins** at boot when `environment != "local"`.
15. **🟡 Validate phone numbers as E.164.**
16. **🟡 Add backend rate limit on `POST /events`** (auth'd users can fill the hypertable).
17. **🟡 Fix `voice_service.dart` deprecated `roomOptions` parameter.** Move into the `Room()` constructor as the deprecation warning suggests.
18. **🟡 Real-device battery-drain benchmark.** PRD success metric, can't be measured in CI.

## Recommended ordering for the next session

```
Task 0   (new) flutter create . + bundle id + firebase config files + CI diagnose
Task 1   (done) state audit                                     ← THIS FILE
Task 2   design system extraction → lib/core/theme/             ← from kickoff
Task 3   2 reference screens (onboarding + radar map)           ← from kickoff
[CHECKPOINT — show user, get approval]
Task 4   restyle remaining 12 v1 screens                         ← from kickoff
Task 4b  build the 7 missing v1 screens                          ← new
Task 4c  battery-suspend fix + voice deprecation cleanup         ← new
Task 4d  security hardening (rate limit, JWT guard, admin gate)  ← new
Task 5   smoke test end-to-end                                   ← from kickoff
Task 6   ship-readiness (privacy policy, ToS, store assets)      ← from kickoff
```

The kickoff explicitly told me to STOP after the audit. I have stopped. Nothing has been changed. No code touched. Awaiting review and instructions.

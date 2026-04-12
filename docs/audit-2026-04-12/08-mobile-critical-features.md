# 08 — Mobile critical-feature reality check

## Battery-aware location publishing — partially real

`apps/mobile/lib/features/map/location_service.dart` (`AdaptiveLocationService`):

- ✅ Adaptive cadence is implemented: speed > 10 km/h → 5 s + high accuracy, > 1 km/h → 15 s + medium, otherwise 30 s + low. `_maybeAdjust(p)` swaps the interval and restarts the geolocator stream.
- ✅ Heartbeat timer ensures frames keep flowing when the user is stationary (the position stream alone doesn't fire).
- ✅ Permission flow handles `denied` / `deniedForever` correctly.

### 🟠 Battery-suspend code is dead

`onBatteryUpdate(int? batteryPct)` is supposed to suspend the stream when battery drops below 15%. Two problems:

1. **No caller ever invokes it.** Grep `lib/` for `onBatteryUpdate` returns only the definition. `LiveTripController` reads battery from `geolocator` Position frames but never feeds it back to the location service.
2. **It never restarts** when the battery recovers. Once suspended, you stay dark for the rest of the session unless you call `start()` again.

**Fix scope:** small. Wire `onBatteryUpdate` from the controller layer (or read battery via `battery_plus`), and add a `resume()` path keyed off battery_pct or charging state.

This matters because the PRD lists `< 4% battery drain / hour` as a v1 success metric — the suspend path is the headline feature for that promise.

## LiveKit voice — real, with one deprecation

`apps/mobile/lib/features/voice/voice_service.dart`:

- ✅ Connects via `livekit_client` `Room.connect(url, token)` to a real LiveKit room.
- ✅ Joins muted by default; `setTalking(bool)` toggles `localParticipant.setMicrophoneEnabled`.
- ✅ Backend mints the JWT token with the right `video` grant (`canPublish`, `canSubscribe`).
- 🟡 `roomOptions:` parameter on `Room.connect` is flagged deprecated by the analyzer (info-level). Should move `RoomOptions` into the `Room()` constructor. Doesn't block anything but the analyzer noise.

`features/voice/ptt_button.dart` is a button widget that calls `setTalking` on press / release. There is **no full-screen PTT comms screen** matching the `pack_voice_comms` Stitch design. The current implementation is a tiny FAB on the trip map.

## Outbound location queue — real

`apps/mobile/lib/features/map/outbound_queue.dart`:

- ✅ Hive box `pp.outbound_locations` keyed by auto-incrementing int → JSON-encoded frame strings.
- ✅ Cap at 1000 entries to avoid stale-data drain.
- ✅ `drain(send)` calls a sender for each entry in insertion order, deletes on success, breaks on first failure so the queue stays consistent.
- ✅ `LiveTripController._enqueue` writes when WS is down; `_drainQueue` runs on reconnect.

This works. Verified by the code path in `LiveTripController.publishLocation`.

## FCM push — guarded but never tested in CI

`apps/mobile/lib/features/push/push_service.dart`:

- ✅ Initialises Firebase, requests notification permission, calls `getToken`, POSTs to `/devices`.
- ✅ Listens for `onTokenRefresh` and re-registers.
- ✅ Wrapped in try/catch — if `Firebase.initializeApp()` throws (no `google-services.json`) it silently skips.
- 🔴 **No Firebase config files exist:** grep for `google-services.json` and `GoogleService-Info.plist` returns nothing under `apps/mobile/`. There's also no `lib/firebase_options.dart` from FlutterFire CLI.

So push is "wired" but the only thing it can do today is print `Firebase init skipped` and noop. No production push will ever send until the config files are added.

## Crash detector — real for v1, untested

`apps/mobile/lib/features/safety/crash_detector.dart`:

- ✅ Uses `sensors_plus` `userAccelerometerEventStream` (excludes gravity).
- ✅ Magnitude > 4 g threshold + 30 s cooldown.
- ✅ `start(onSpike)` callback wired in `trip_map_screen.dart`'s `initState` to send a `crash` frame.
- 🟡 No automated test, no real-device threshold tuning. 4 g is a reasonable starting point but the false-positive rate over a pothole-heavy Indian highway is unknown.

## Map providers and tile cache — real

- `lib/features/map/map_providers.dart` — Mapbox / Google / Mappls / HERE / TomTom / OSRM enum with persisted user choice.
- `lib/features/map/tile_cache.dart` — Hive-backed Mapbox tile cache + `CachedMapboxTileProvider`. Works for Mapbox style; for other providers it falls back to `NetworkTileProvider` (no offline cache).
- The Map style picker in `trip_map_screen` queries `/maps/providers` to mark each option as "configured on server" honestly.

## Summary

| Subsystem | Status | Notes |
|---|---|---|
| Adaptive location | 🟡 partial | Battery-suspend code is dead |
| LiveKit voice | 🟢 real | Deprecated `roomOptions` param |
| Outbound queue | 🟢 real | Works |
| FCM push client | 🔴 wired but no config | Need `google-services.json` + `GoogleService-Info.plist` |
| Crash detector | 🟢 real | Needs real-device tuning |
| Tile providers | 🟢 real | Cache only for Mapbox |
| SOS button | 🟢 real | Two-tap arming |

# Session 2 — Radar Map Restyle Findings

> **Status:** All 7 findings resolved in PR #5 (Session 3 Track 1 quality
> pass, merged). This file is kept as historical reference.

Smells/concerns logged during Task 6 (visual-only restyle of `trip_map_screen.dart`,
`eta_panel.dart`, `ptt_button.dart`). None of these were fixed in this task — they
are visual-layer-adjacent observations for a future cleanup pass.

## `trip_map_screen.dart`

- `_StraightLine.waypoints` is typed as the untyped `List`. It also reaches into
  `w.latLng as LatLng` without a shared interface. Same pattern appears in
  `_frameAll`, `_downloadOfflineTiles`, and `_onLongPress`. A typed waypoint DTO
  would tighten this considerably.
- `_colorForUser` calls
  `(trip.members as List).cast<dynamic>().firstWhere(... orElse: () => null)`
  and then duck-types `m.color`. There's an existing trip-member model somewhere
  — this should be typed against it.
- `withOpacity` is used in several places even though `kinetic_path_tokens.dart`
  already notes the deprecation and the migration to `Color.withValues(alpha:)`.
  When Flutter pin moves past 3.27, sweep the whole file.
- The ETA `IconButton` in the app-bar actions opens the `EtaPanel` via
  `showModalBottomSheet` without `useSafeArea: true`; on the notch devices the
  drag-handle sits under the status bar if the user drags it to full height.
- The cloud-connection indicator (amber queue-count badge in the app bar
  `Padding`) uses raw `Colors.amber` / `Colors.greenAccent` / `Colors.redAccent`.
  Not restyled in this pass because it's an ops indicator, not brand surface,
  but it should eventually map to token-based semantic colors.

## `eta_panel.dart`

- Members are labelled `Member ${m.userId.substring(0, 6)}` — there's clearly
  no display name plumbed through to the ETA model, only the raw user id. The
  restyled row typography highlights the problem because the titleSmall slot
  looks like it expects a real name.
- `_formatDuration` does its own `m / 60` math instead of using Flutter's
  `Duration` formatting helpers. Minor.

## `ptt_button.dart`

- The comment on `PttButton` promises "existing pulse animation logic" (per the
  Task 6 brief), but there is no animation controller or pulse — just a static
  color switch on `_talking`. The task said to preserve it; there was nothing
  to preserve. Worth adding a real pulse on `_talking` in a later polish pass.
- Error surface is a small red `Text` above the button with no dismiss. A
  `SnackBar` or in-token error chip would be more consistent with the rest of
  the app.

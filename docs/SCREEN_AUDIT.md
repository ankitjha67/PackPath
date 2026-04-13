# Screen audit — Session 3 Track 3 prep

_Generated 2026-04-13. Bar: `trip_map_screen.dart`, `onboarding_screen.dart`, `hazard_banner.dart`._

## Summary

| Screen | Path | Route | Score | Grade | Top gap |
|--------|------|-------|-------|-------|---------|
| _populated below_ |

## Per-screen detail

### ChatScreen

- **File**: `apps/mobile/lib/features/chat/chat_screen.dart`
- **Route**: `/trips/:id/chat`
- **Score**: 3/12 (rough)
- **Breakdown**:
  1. Theme adherence: 1/2 — uses `colorScheme.secondaryContainer` and `textTheme.bodySmall` for system bubbles, but every bubble has magic `EdgeInsets`, raw `BorderRadius.circular(12)`, hardcoded `fontSize: 12`, and no `AppSpacing` / `AppRadii` anywhere.
  2. Loading: 1/2 — plain `Center(CircularProgressIndicator())` for history; no skeleton, no hint that WS is also streaming live frames behind it.
  3. Error: 0/2 — `Center(Text('Error: $e'))`, no retry button, no explanation.
  4. Empty: 0/2 — if a trip has zero messages the ListView just renders blank; no "start the conversation" CTA or illustration.
  5. Spacing: 0/2 — `EdgeInsets.symmetric(vertical: 4, horizontal: 12/16)` sprinkled with raw numbers, no `surface` vs `surfaceContainer` layering between the list and the input bar.
  6. Feedback: 1/2 — `IconButton.filled` on send and an optimistic local echo are nice, but send failures are swallowed silently (no SnackBar).
- **Top 3 fixes** (priority order):
  1. Dedicated empty state with an icon + "Break the ice — say hi to the pack" CTA.
  2. Error state with a retry button that reinvalidates `chatHistoryProvider(tripId)`.
  3. Restyle `_MessageBubble` against `colorScheme.surfaceContainer` / `surfaceContainerHigh`, `textTheme.bodyMedium` + `labelSmall`, `AppRadii.lg`, `AppSpacing.sm/md`.

### AuditLogScreen

- **File**: `apps/mobile/lib/features/audit/audit_log_screen.dart`
- **Route**: `/audit`
- **Score**: 3/12 (rough)
- **Breakdown**:
  1. Theme adherence: 0/2 — `ListTile` + `Divider(height: 1)` defaults, no `textTheme` use, no tokens. The whole 46-line file is Material defaults.
  2. Loading: 1/2 — plain centered spinner.
  3. Error: 0/2 — `Center(Text('Error: $e'))`, no retry.
  4. Empty: 1/2 — has a `'Nothing logged yet'` placeholder but no icon and no hint of what populates the list.
  5. Spacing: 0/2 — just the `Divider(height: 1)` between rows, no padding, no surface layering.
  6. Feedback: 1/2 — read-only, nothing to feedback, but no refresh gesture either.
- **Top 3 fixes** (priority order):
  1. `RefreshIndicator` wrapping the list + retry on error that reinvalidates the `_auditProvider`.
  2. Empty state with a shield icon and "We log every time someone queries your location — nothing here means no one has".
  3. Restyle rows: `Container` per entry with `surfaceContainerLow`, `AppRadii.lg`, `AppSpacing.md` padding, `titleSmall` for action, `bodySmall` + `onSurfaceVariant` for the timestamp.

### PersonalStatsScreen

- **File**: `apps/mobile/lib/features/analytics/personal_stats_screen.dart`
- **Route**: `/me/stats`
- **Score**: 3/12 (rough)
- **Breakdown**:
  1. Theme adherence: 1/2 — uses `textTheme.titleLarge` for the value, but every tile is a raw Material `Card` + `ListTile`, no `AppSpacing`, no surface layering.
  2. Loading: 1/2 — plain spinner.
  3. Error: 0/2 — `Center(Text('Error: $e'))`.
  4. Empty: 0/2 — if the backend returns nulls for the stat fields, the tiles render `'null km'` etc. with no graceful empty path.
  5. Spacing: 0/2 — `EdgeInsets.all(16)` and nothing else; every tile is a `Card` default.
  6. Feedback: 1/2 — static screen, no refresh gesture, no retry.
- **Top 3 fixes** (priority order):
  1. Graceful null handling — if `total_distance_km == null`, show "Take your first trip to unlock stats" instead of `'null km'`.
  2. Replace raw `Card` + `ListTile` with Kinetic Path glass tiles: `Container(decoration: surfaceContainer, borderRadius: AppRadii.lg)`, `labelSmall` for label, `headlineSmall` for value (matches the ETA panel pattern).
  3. `RefreshIndicator` wrapper + retry path on error.

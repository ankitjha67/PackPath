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

### TripListScreen

- **File**: `apps/mobile/lib/features/trips/trip_list_screen.dart`
- **Route**: `/trips`
- **Score**: 4/12 (rough)
- **Breakdown**:
  1. Theme adherence: 0/2 — zero theme tokens. `ListTile`, `Divider(height: 1)`, `DefaultTabController` defaults, `EdgeInsets.all(32)`. No textTheme, no AppSpacing, no surface layering.
  2. Loading: 1/2 — plain centered spinner.
  3. Error: 1/2 — `ListView` with a `Padding + Text('Failed to load trips:\n$err')` — at least it's scrollable for RefreshIndicator to work, but still no retry button.
  4. Empty: 1/2 — per-tab `emptyMessage` is passed in, but it's just centered Text with no icon, no illustration, no "Create trip" CTA (the FAB is at the screen level and not within-the-empty-state).
  5. Spacing: 0/2 — magic `EdgeInsets.all(32)`, `Divider(height: 1)`, no surface elevation between tab bar and list.
  6. Feedback: 1/2 — `RefreshIndicator` is wired, FAB for new trip, popup menu for nav. No loading state on the popup-menu nav actions (fine, sync nav), no destructive-action confirmation for "leave trip" (which doesn't exist on this screen yet).
- **Top 3 fixes** (priority order):
  1. Full Kinetic Path restyle: each trip row becomes a `Container(surfaceContainer, AppRadii.lg, AppSpacing.md padding)` with `titleMedium` for trip name, `labelSmall` for status + members + join code, no `Divider` — use `AppSpacing.sm` gaps instead.
  2. Proper empty state per tab: illustration / `Icons.explore` + headline + subheadline + a `FilledButton.icon` CTA that delegates to the FAB.
  3. Error state with retry button that calls `ref.invalidate(myTripsProvider)` instead of just displaying the exception.

### ShareTripScreen

- **File**: `apps/mobile/lib/features/trips/share_trip_screen.dart`
- **Route**: `/trips/:id/share`
- **Score**: 5/12 (rough)
- **Breakdown**:
  1. Theme adherence: 1/2 — uses `textTheme.headlineSmall` and `bodyMedium` for trip name + help text, but the join code is a hardcoded `TextStyle(fontSize: 36, letterSpacing: 8, w700)`. QR wrapper uses `Colors.white` (OK for QR readability) and magic `BorderRadius.circular(16)`.
  2. Loading: 1/2 — plain centered spinner.
  3. Error: 0/2 — bare `Center(Text('Error: $e'))` with no retry.
  4. Empty: 2/2 — N/A, trip always resolves or errors.
  5. Spacing: 0/2 — magic `EdgeInsets.all(24)` + `SizedBox(height: 16/24)` throughout, no `AppSpacing`.
  6. Feedback: 1/2 — Copy button shows a `SnackBar('Code copied')`, good. But no "share via platform sheet" fallback for users who can't show the QR to the other phone.
- **Top 3 fixes** (priority order):
  1. Swap the hardcoded `TextStyle(fontSize: 36)` for `textTheme.displaySmall` with the SpaceGrotesk family (bar-matching) and keep `letterSpacing: 8` only.
  2. Add a "Share…" button that calls `Share.share('Join my PackPath: packpath://join/<code>')` via the `share_plus` package (or document the gap if the package isn't in pubspec yet — check before implementing).
  3. Replace magic paddings with `AppSpacing.lg / AppSpacing.base`, wrap the QR in an `AppRadii.xl` `Container` with `surfaceContainerHigh` backing so it reads as a layered card.

### ExpensesScreen

- **File**: `apps/mobile/lib/features/expenses/expenses_screen.dart`
- **Route**: `/trips/:id/expenses`
- **Score**: 5/12 (rough)
- **Breakdown**:
  1. Theme adherence: 1/2 — uses `surfaceContainerHighest` for the balances footer (good!) and `textTheme.titleMedium`, but the balance sign uses hardcoded `Colors.green` / `Colors.red` instead of `colorScheme.tertiary` / `colorScheme.error`.
  2. Loading: 1/2 — `Center(CircularProgressIndicator())` for expenses, `Text('Computing balances…')` for balances. Inconsistent styles.
  3. Error: 0/2 — `Center(Text('Error: $e'))` in two places, no retry.
  4. Empty: 1/2 — `Center(Text('No expenses logged yet'))` — present but no icon/CTA, and the FAB sits outside the empty state visually.
  5. Spacing: 0/2 — magic numbers (`EdgeInsets.all(16)`, `EdgeInsets.symmetric(vertical: 2)`), no `AppSpacing`.
  6. Feedback: 2/2 — dialog-based add flow, `SnackBar` on add failure, provider invalidation after success. This is the best-graded interaction in the non-gold set.
- **Top 3 fixes** (priority order):
  1. Drop `Colors.green` / `Colors.red` for `colorScheme.tertiary` / `colorScheme.error` so the ledger obeys the design system (and dark mode).
  2. Empty state with a `Icons.receipt_long` + "Log the first expense to start the split" headline and a `FilledButton.icon` CTA that calls the same `_add` handler as the FAB.
  3. Consistent error handling across both providers with a retry button that calls `ref.invalidate(_expensesProvider(tripId))` / `_balancesProvider(tripId)`.

### TripRecapScreen

- **File**: `apps/mobile/lib/features/recap/recap_screen.dart`
- **Route**: `/trips/:id/recap`
- **Score**: 5/12 (rough)
- **Breakdown**:
  1. Theme adherence: 1/2 — uses `textTheme.titleMedium` + `titleLarge` + `bodyMedium` and `colorScheme.primary` for the heatmap bars, but every stat is a raw Material `Card` with no `AppRadii`, `AppSpacing`, or surface layering.
  2. Loading: 1/2 — plain centered spinner.
  3. Error: 0/2 — bare `Center(Text('Error: $e'))`.
  4. Empty: 2/2 — N/A, the server always returns some structure for recap.
  5. Spacing: 0/2 — `EdgeInsets.all(16/8/1)` magic numbers throughout.
  6. Feedback: 1/2 — static, read-only, no refresh gesture.
- **Top 3 fixes** (priority order):
  1. Replace raw `Card` + `_StatCard(Row with Spacer)` with Kinetic Path glass tiles: `Container(surfaceContainer, AppRadii.lg, AppSpacing.md)`, `labelSmall` for label, `displaySmall` for value — match the HUD card pattern in `trip_map_screen.dart`.
  2. Member list rows: drop the fabricated `'Member ${userId.substring(0, 6)}'` in favour of a leading color dot keyed on `tripDetailProvider(tripId).members[userId].color` (same fix shipped in Session 3 Track 1 for `eta_panel.dart`).
  3. Heatmap upgrade: add hour labels under the bars, use `colorScheme.primary` for the current hour and `primaryContainer` for the rest, add a "local time" toggle since the label already says "(UTC)".

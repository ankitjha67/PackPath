# Screen audit — Session 3 Track 3 prep

_Generated 2026-04-13. Bar: `trip_map_screen.dart`, `onboarding_screen.dart`, `hazard_banner.dart`._

## Summary

| Screen | Path | Route | Score | Grade | Top gap |
|--------|------|-------|------:|-------|---------|
| ChatScreen | `chat/chat_screen.dart` | `/trips/:id/chat` | 3 | rough | no empty / error / retry states, magic spacing, bubbles ignore tokens |
| AuditLogScreen | `audit/audit_log_screen.dart` | `/audit` | 3 | rough | Material defaults, no empty/error refinement, no refresh |
| PersonalStatsScreen | `analytics/personal_stats_screen.dart` | `/me/stats` | 3 | rough | no null handling, raw `Card`+`ListTile`, no error/retry |
| TripListScreen | `trips/trip_list_screen.dart` | `/trips` | 4 | rough | zero tokens, weak empty state, no error retry |
| ShareTripScreen | `trips/share_trip_screen.dart` | `/trips/:id/share` | 5 | rough | hardcoded display style, no share-sheet, bare error |
| ExpensesScreen | `expenses/expenses_screen.dart` | `/trips/:id/expenses` | 5 | rough | hardcoded `Colors.green`/`red`, weak empty state, bare error |
| TripRecapScreen | `recap/recap_screen.dart` | `/trips/:id/recap` | 5 | rough | raw `Card` stats, fake "Member abc123" labels, bare error |
| LoginScreen | `auth/login_screen.dart` | `/login` | 6 | acceptable | wordmark hardcoded, magic spacing, no field validation |
| OtpScreen | `auth/otp_screen.dart` | `/otp` | 6 | acceptable | no resend CTA, magic spacing, OTP field undersized |
| CreateTripScreen | `trips/create_trip_screen.dart` | `/trips/new` | 6 | acceptable | missing start/end/max fields, magic spacing |
| JoinTripScreen | `trips/join_trip_screen.dart` | `/trips/join` | 6 | acceptable | no QR-scan path, raw error strings, magic spacing |
| PrivacyScreen | `privacy/privacy_screen.dart` | `/privacy` | 9 | acceptable | magic spacing, non-tappable privacy@ email |
| PlansScreen | `billing/plans_screen.dart` | `/plans` | 10 | polished | `BorderRadius.circular(16/12)` instead of `AppRadii.xl/full`, magic spacing |

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

### LoginScreen

- **File**: `apps/mobile/lib/features/auth/login_screen.dart`
- **Route**: `/login`
- **Score**: 6/12 (acceptable)
- **Breakdown**:
  1. Theme adherence: 1/2 — uses `textTheme.bodyLarge` for the tagline and `colorScheme.error` for the error text, but the "PackPath" wordmark is a hardcoded `TextStyle(fontSize: 36, w700)` instead of `textTheme.displaySmall` + the SpaceGrotesk family.
  2. Loading: 1/2 — button swaps to a `CircularProgressIndicator(strokeWidth: 2)` during busy — present but a pulse-with-label would match Kinetic Path better.
  3. Error: 1/2 — inline `Text` with error color, no retry button (tap-to-resend is implicit), no field-level validation.
  4. Empty: 2/2 — N/A (form screen).
  5. Spacing: 0/2 — `EdgeInsets.all(24)` + `SizedBox(height: 8/16/40)` magic numbers, no `AppSpacing`.
  6. Feedback: 1/2 — disabled button during busy, inline error. No "Resend OTP after 30 s" affordance.
- **Top 3 fixes** (priority order):
  1. Wordmark becomes `Text('PackPath', style: textTheme.displayMedium)` so it picks up the KP family and responsive sizing.
  2. Replace every magic `SizedBox` with `AppSpacing.sm/md/base/lg` and the outer padding with `AppSpacing.lg`.
  3. Add inline phone validation (country code + length) and show it as `inputDecoration.errorText` so the field itself is the error surface instead of a separate `Text`.

### OtpScreen

- **File**: `apps/mobile/lib/features/auth/otp_screen.dart`
- **Route**: `/otp?phone=...&debug=...`
- **Score**: 6/12 (acceptable)
- **Breakdown**:
  1. Theme adherence: 1/2 — uses `textTheme.bodySmall` for the debug OTP line and `colorScheme.error`, but the OTP field is a hardcoded `TextStyle(fontSize: 24, letterSpacing: 12)` instead of a `headlineSmall` copy.
  2. Loading: 1/2 — same in-button `CircularProgressIndicator(strokeWidth: 2)` as LoginScreen.
  3. Error: 1/2 — inline `Text` with error color; no "resend" CTA after N failures.
  4. Empty: 2/2 — N/A (form).
  5. Spacing: 0/2 — `EdgeInsets.all(24)` + `SizedBox(height: 4/8/16/24)` magic numbers.
  6. Feedback: 1/2 — disabled button, post-verify navigation to `/trips`, fire-and-forget push registration. No "didn't receive the code — resend" button even though the backend supports `/auth/otp/request` re-calls.
- **Top 3 fixes** (priority order):
  1. Add a "Resend code" text button that appears after a 30 s countdown and calls `authRepository.requestOtp(widget.phone)` — also reset `_controller`.
  2. Promote the OTP input to `textTheme.headlineMedium` so it reads as the primary interaction (the hardcoded `fontSize: 24` is smaller than the bar for a primary input).
  3. Replace magic `SizedBox` + `EdgeInsets.all(24)` with `AppSpacing.*` — matches the LoginScreen fix, same patch style.

### CreateTripScreen

- **File**: `apps/mobile/lib/features/trips/create_trip_screen.dart`
- **Route**: `/trips/new`
- **Score**: 6/12 (acceptable)
- **Breakdown**:
  1. Theme adherence: 1/2 — uses `colorScheme.error` for the error line; nothing else from the theme. Relies entirely on Material defaults for the text field and button.
  2. Loading: 1/2 — in-button `CircularProgressIndicator(strokeWidth: 2)`.
  3. Error: 1/2 — inline Text, no retry button (implicit re-tap).
  4. Empty: 2/2 — N/A (form).
  5. Spacing: 0/2 — `EdgeInsets.all(24)` + `SizedBox(height: 8/16)` magic numbers.
  6. Feedback: 1/2 — disabled button during busy + provider invalidation on success. No confirmation that this trip is created, just a navigate-away.
- **Top 3 fixes** (priority order):
  1. Add fields for start/end window and max members — the backend `POST /trips` already accepts them but the current form only sends `name`. Without these the free-tier enforcement bites unexpectedly.
  2. Replace magic spacing with `AppSpacing.*` and promote the section header to `textTheme.headlineSmall` so the empty state doesn't feel like a 3-field page with no context.
  3. Inline validation: require `name.length >= 3` and show as `inputDecoration.errorText` instead of a separate `Text` at the bottom.

### JoinTripScreen

- **File**: `apps/mobile/lib/features/trips/join_trip_screen.dart`
- **Route**: `/trips/join`
- **Score**: 6/12 (acceptable)
- **Breakdown**:
  1. Theme adherence: 1/2 — uses `colorScheme.error` for the error line; join-code field is hardcoded `TextStyle(fontSize: 24, letterSpacing: 8)` instead of `headlineMedium`.
  2. Loading: 1/2 — in-button `CircularProgressIndicator(strokeWidth: 2)`.
  3. Error: 1/2 — inline Text, client-side length check for 6-char code is fine, but backend errors render as `'Could not join: $e'` verbatim.
  4. Empty: 2/2 — N/A (form).
  5. Spacing: 0/2 — `EdgeInsets.all(24)` + `SizedBox(height: 16)` magic.
  6. Feedback: 1/2 — disabled button during busy. No QR-scan path on this screen even though the app icon in `trip_list_screen.dart` uses `Icons.qr_code_scanner`.
- **Top 3 fixes** (priority order):
  1. Wire a QR scanner path (reuse `mobile_scanner` if available, or document the gap): "Scan the code your friend is showing" is the companion to `ShareTripScreen` and it's missing here.
  2. Parse common backend errors into friendly copy: `invalid_code` → "That code doesn't match any trip", `trip_full` → "This trip is full on the free tier", `trip_ended` → "This trip has ended".
  3. Promote the join-code input to `headlineMedium` and replace magic spacing with `AppSpacing.*` — same patch as LoginScreen / OtpScreen.

### PrivacyScreen

- **File**: `apps/mobile/lib/features/privacy/privacy_screen.dart`
- **Route**: `/privacy`
- **Score**: 9/12 (acceptable)
- **Breakdown**:
  1. Theme adherence: 1/2 — uses `textTheme.headlineSmall`, `titleMedium`, `bodySmall`; everything else is Material defaults with magic `EdgeInsets.all(20)` and `SizedBox(height: 8/24/12/32)`.
  2. Loading: 2/2 — N/A (static content).
  3. Error: 2/2 — N/A (static content).
  4. Empty: 2/2 — N/A (static content).
  5. Spacing: 1/2 — clear hierarchy with sectioning, but every value is a raw number instead of `AppSpacing.*`.
  6. Feedback: 1/2 — purely informational; the "email privacy@packpath.app" line is a bare string with no `launchUrl('mailto:...')` wiring.
- **Top 3 fixes** (priority order):
  1. Replace every magic `EdgeInsets` / `SizedBox` with `AppSpacing.*` — this is a 10-minute patch since the content is stable.
  2. Make the "Email privacy@packpath.app" line a `TextButton.icon(Icons.mail_outline, ...)` that calls `launchUrl('mailto:privacy@packpath.app?subject=Delete my account')`.
  3. Section headers become glass pills (`Container(surfaceContainer, AppRadii.full, AppSpacing.sm h / AppSpacing.xs v)`) so the page reads as structured instead of a long text blob.

### PlansScreen

- **File**: `apps/mobile/lib/features/billing/plans_screen.dart`
- **Route**: `/plans`
- **Score**: 10/12 (polished)
- **Breakdown**:
  1. Theme adherence: 1/2 — uses `textTheme.headlineSmall/titleMedium/labelSmall/bodySmall` and `colorScheme.primary` / `onPrimary` for the POPULAR badge and the featured card border. Only gap: `BorderRadius.circular(16/12)` instead of `AppRadii.xl/full`, and no `AppSpacing`.
  2. Loading: 2/2 — N/A (static).
  3. Error: 2/2 — N/A (static).
  4. Empty: 2/2 — N/A (static).
  5. Spacing: 1/2 — clear hierarchy, but magic `EdgeInsets.all(16/20)` and `SizedBox(height: 4/8/12/16/24)` throughout.
  6. Feedback: 2/2 — honest `SnackBar('Billing flow lands in the polish week — stay tuned.')` on the stub CTA. This is the best-graded feedback in the non-gold set because it explicitly tells the user the button is a stub.
- **Top 3 fixes** (priority order):
  1. Swap `BorderRadius.circular(16)` → `AppRadii.xl` (8 dp) and `BorderRadius.circular(12)` → `AppRadii.full` so the card corners match the rest of the app (the current 16 dp rounds are too pillowy for Kinetic Path).
  2. Replace every magic `EdgeInsets` / `SizedBox` with `AppSpacing.*`.
  3. When the real Razorpay + Stripe flow lands, the featured card should also use `tokens.ctaGradient` on its CTA button to match the PTT button — currently it's a plain `FilledButton`.

## Structural gaps

Navigation analysis of `apps/mobile/lib/routing/router.dart` + `grep` for `context.push` / `context.go` across the codebase.

### Settings hub — missing

There is no Settings screen. The four "me / admin / billing / privacy" routes land on the following single entry points:

| Route | Entry points | Reachable from |
| ----- | ------------ | -------------- |
| `/privacy` | 2 | `trip_list_screen.dart` app-bar popup + `trip_map_screen.dart` app-bar popup |
| `/plans` | 2 | `trip_list_screen.dart` popup + `trip_map_screen.dart` popup |
| `/audit` | **1** | `trip_list_screen.dart` popup menu only |
| `/me/stats` | **1** | `trip_list_screen.dart` popup menu only |

**Impact**: a user who deep-links straight into `/trips/:id` (e.g. via the `packpath://join/<code>` flow) and never navigates back to `/trips` has no way to reach `/audit` or `/me/stats`. The four routes are also hidden behind a `PopupMenuButton<String>` (kebab menu) with no icons next to each row — discoverability is poor.

**Fix**: ship a `SettingsScreen` at `/settings` that exposes each as a labeled list row with the right icon (`shield_outlined` privacy, `workspace_premium_outlined` plans, `insights_outlined` audit, `query_stats` stats). Drop the popup-menu items from `trip_list_screen.dart` and `trip_map_screen.dart` in favour of a single `IconButton(Icons.settings_outlined)` that pushes `/settings`. This also prepares the ground for Session 5's account deletion / sign-out row.

### Trip edit / settings — missing

No `/trips/:id/edit` or `/trips/:id/settings` route exists in `router.dart`. The backend supports:

- `POST /trips/{id}/end` — owner ends trip
- Implicit leave via backend (not currently called from mobile)
- Trip rename (if any) — not exposed
- Member kick (if any) — not exposed
- Member role change — not exposed

The only trip-state mutation accessible on the mobile side is the `Ghost mode` toggle in the `trip_map_screen.dart` popup menu. There is **no** "End trip" / "Leave trip" button anywhere in the app — a `grep -n "end trip\|leaveTrip\|Icons.logout"` returns zero matches.

**Fix**: ship a `TripSettingsScreen` at `/trips/:id/edit` pushed from a `Icons.settings_outlined` in the `trip_map_screen.dart` app bar, covering at least:

1. Rename trip (owner only).
2. Members list with a "remove" swipe action (owner only).
3. Leave trip (members).
4. End trip (owner, destructive — red `FilledButton.tonal` with a confirmation dialog).

### Dead-end routes

Every route in `router.dart` has at least one `context.push` / `context.go` reference. Good — no literal dead-end routes. But two routes (`/audit`, `/me/stats`) have exactly one entry point, both buried in the same kebab menu; functionally dead-end-adjacent until the Settings hub lands.

### Admin audit entry point

`/audit` currently shows `/me/audit` (the logged-in user's own audit rows). There is no separate admin view of "who queried user X's location". Backend currently lacks a `/admin/audit/{user_id}` route, so this is a backend gap more than a screen gap — **flagged here for Session 4+**, not fixable in the Track 3 restyle pass.

### Profile / account — missing

No `/me` or `/me/profile` screen. Backend has `GET /me` and `PATCH /me` for display name + avatar, but the mobile app never renders or edits them. Call this out as a prerequisite for the Settings hub — the top row should be "Your profile" with the phone number + display name + avatar edit affordance.

## Recommended Track 3 execution order

Ranked by blast radius + score gap. The structural gaps land first because they fix discoverability for everything else; then the sub-6 screens; then the 6-9 screens only if there's time. 10+ screens are explicitly skipped.

### Tier 1 — Structural (do first, unblocks everything else)

1. **`SettingsScreen` at `/settings`.** Single hub exposing Profile (new), Plans, Privacy, Audit, Your stats, and a future Sign out. Replaces the popup-menu items in `trip_list_screen.dart` and `trip_map_screen.dart` with one `Icons.settings_outlined` button. Fixes `/audit` + `/me/stats` discoverability immediately. *Why first*: cheap (one new screen + two small edits), and it's a prerequisite for any future account-deletion / sign-out work.
2. **`ProfileScreen` at `/me`** (pushed from Settings). Renders phone + display name + avatar via `GET /me`, edits via `PATCH /me`. *Why second*: backend already supports it; the Settings hub has a dead link without it.
3. **`TripSettingsScreen` at `/trips/:id/edit`.** Rename / members / leave / end-trip destructive action. Push from a new `Icons.settings_outlined` in `trip_map_screen.dart`'s app bar. *Why third*: unblocks the "I want to leave this trip" bug that currently has no UI, and gives the owner a way to end a trip without poking the API directly.

### Tier 2 — Rough screens (score < 6)

Order chosen to pair related patches together so reviewers can batch them.

4. **`ChatScreen` (3/12)** — empty state + error retry + bubble tokens. *Why before TripListScreen*: chat is deep in the trip flow, users hit it daily, and the current zero-empty-state is the biggest daily paper-cut.
5. **`TripListScreen` (4/12)** — full Kinetic Path restyle of rows + proper per-tab empty states + error retry. *Why second in tier*: `/trips` is the home screen after login; the restyle here lands the biggest "app feels premium" win.
6. **`AuditLogScreen` (3/12)** + **`PersonalStatsScreen` (3/12)** — paired restyle, they share the same "read-only list backed by `/me/*`" shape. Glass tiles, retry buttons, null-safe empty copy. *Why batched*: one reviewer pass covers both, reuses the same row widget.
7. **`ExpensesScreen` (5/12)** — drop hardcoded `Colors.green`/`red`, add empty state CTA, error retry. Already has the best feedback loop (SnackBar on add), so this is mostly a visual pass.
8. **`TripRecapScreen` (5/12)** — replace `Card` stats with glass tiles, kill the "Member abc123" fake label (reuse the Session 3 Track 1 fix from `eta_panel.dart`), upgrade the heatmap. *Why late*: recap is post-trip, lower traffic.
9. **`ShareTripScreen` (5/12)** — display style via theme, wire `share_plus`, glass card around the QR. *Why last in tier*: functional already, cosmetic upgrade.

### Tier 3 — Acceptable screens (6-9), only if budget allows

10. **`LoginScreen` (6/12)** + **`OtpScreen` (6/12)** — paired `AppSpacing` patch + wordmark / OTP field typography + Resend CTA on OTP. First impressions matter but the screens work; tackle after the tier-2 work lands.
11. **`CreateTripScreen` (6/12)** — the missing `start_at` / `end_at` / `max_members` fields are actually a feature gap (free-tier enforcement bites unexpectedly). Worth escalating to Tier 1 if product wants it before beta.
12. **`JoinTripScreen` (6/12)** — QR scanner path + friendly backend-error copy. Pairs with `ShareTripScreen`; consider doing both in one patch.
13. **`PrivacyScreen` (9/12)** — 10-minute `AppSpacing` sweep + tappable mailto. Smallest patch in the doc.

### Tier 4 — Skip (already polished)

14. **`PlansScreen` (10/12)** — only needs `AppRadii.xl/full` instead of `BorderRadius.circular(16/12)` and `AppSpacing` sweep. 5 min patch, nice-to-have, not blocking.
15. **`TripMapScreen`** — bar-setter (Session 2 + Session 3 Track 1 + Track 2). Don't touch except to add the Tier 1 Settings / TripSettings entry points.
16. **`OnboardingScreen`** — bar-setter. Don't touch.
17. **`HazardBanner`** — bar-setter. Don't touch.

### Estimated session carve-up

- **Track 3a** (one session): Tier 1 structural work (3 screens). Biggest impact, smallest surface area per screen since they're mostly wiring.
- **Track 3b** (one session): Tier 2 screens, batched (items 4-9). Six rough screens in one restyle pass, reviewing against `trip_map_screen.dart` / `hazard_banner.dart` as the bar.
- **Track 3c** (optional): Tier 3 if time remains. These are polish-over-polish and could slip to Session 4 without hurting beta-readiness.

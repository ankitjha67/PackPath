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

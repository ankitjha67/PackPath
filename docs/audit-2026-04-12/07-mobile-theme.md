# 07 — Mobile theme vs Kinetic Path

## Current state of `apps/mobile/lib/config/theme.dart`

Full file (21 lines):

```dart
import 'package:flutter/material.dart';

class PackPathTheme {
  static const _seed = Color(0xFF3B82F6);

  static ThemeData light() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seed),
        appBarTheme: const AppBarTheme(centerTitle: false),
      );

  static ThemeData dark() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(centerTitle: false),
      );
}
```

That's the entire theme layer. Generic blue (`#3B82F6`) seeded into Material 3's algorithmic palette generator. No fonts, no spacing scale, no radius constants, no glassmorphism, no custom theme extension, no anything Kinetic Path.

## What the Kinetic Path system requires (per `designs/DESIGN_SYSTEM.md`)

| Token role | Required value | Currently? |
|---|---|---|
| `primary` | `#ab3600` (Safety Orange) | ❌ generated from blue seed |
| `primary_container` | `#ff5f1f` | ❌ generated |
| `secondary` | `#2559bd` (Pathfinder Blue) | ❌ generated |
| `tertiary` | `#006493` | ❌ |
| `surface` | `#f9f9fc` | ❌ |
| Display + headline font | Space Grotesk (300–700) | ❌ default Roboto |
| Title + body + label font | Inter (300–700) | ❌ default Roboto |
| Type scale | display-lg → label-sm | ❌ Material defaults |
| Radius `xl` | `0.75rem` (~12px) | ❌ Material defaults |
| Glassmorphism overlay | `surface-container-lowest` + 12px backdrop blur + 85% opacity | ❌ no extension |
| Primary CTA gradient | `primary → primary_container @ 135°` | ❌ no helper |
| No-Line Rule | 1px borders strictly forbidden for sectioning | ❌ existing screens use `Divider`, `OutlineInputBorder`, etc. |

## Required new structure (per kickoff)

```
apps/mobile/lib/core/theme/
├── app_colors.dart        # ColorScheme.light + dark from the locked palette
├── app_typography.dart    # TextTheme using google_fonts (Space Grotesk + Inter)
├── app_spacing.dart       # 4 / 8 / 12 / 16 / 24 / 32 / 48 / 64 constants
├── app_radii.dart         # xs / sm / md / lg / xl / full
└── app_theme.dart         # ThemeData + ThemeExtension<KineticPath> (glassmorphism, gradient)
```

`pubspec.yaml` will need `google_fonts` added — currently absent (confirmed by grep, no `google_fonts` import anywhere in `lib/`).

## Migration plan (for the next session, do not start now)

1. Generate `designs/DESIGN_TOKENS.md` by parsing the Tailwind config blocks from `designs/onboarding/code.html`, `designs/the_radar_map_view/code.html`, `designs/pack_lobby/code.html` (each has a Tailwind config block — confirmed by grep).
2. Hand-write the 5 files in `apps/mobile/lib/core/theme/` based on the consolidated tokens.
3. Add `google_fonts` to `pubspec.yaml`.
4. Update `apps/mobile/lib/app.dart` to call `AppTheme.light()` / `AppTheme.dark()` instead of `PackPathTheme.light/dark`.
5. Delete `lib/config/theme.dart` or leave as a tombstone import.
6. Run `flutter analyze` — every existing screen will still build because they don't reference `PackPathTheme` directly, only `Theme.of(context)`.
7. Commit as `refactor(theme): extract Kinetic Path design system from Stitch mockups`.

## Severity

🔴 **Blocks every restyle**. Until the new theme package exists, restyling individual screens would mean hardcoding hex values into widget code — exactly what the kickoff says to never do. The theme is the foundation everything else builds on.

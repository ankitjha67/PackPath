# PackPath — Design Tokens (Kinetic Path / Precision Utility)

Consolidated from the Tailwind config blocks in `designs/onboarding/code.html`,
`designs/the_radar_map_view/code.html`, `designs/pack_lobby/code.html`,
`designs/pack_chat/code.html`, `designs/pack_voice_comms/code.html`.

This file is generated from Stitch HTML — keep `designs/DESIGN_SYSTEM.md`
as the prose / philosophy spec, this file as the **machine-readable token
list** that `apps/mobile/lib/core/theme/` is built from.

---

## 1. Color palette

### 1.1 Light mode (Material 3 ColorScheme)

Verbatim from `designs/onboarding/code.html` Tailwind config — every other
v1 Stitch screen ships the same palette (verified by diff).

| Material 3 role | Hex | Stitch token name |
| --- | --- | --- |
| `primary` | `#ab3600` | `primary` (Safety Orange) |
| `onPrimary` | `#ffffff` | `on-primary` |
| `primaryContainer` | `#ff5f1f` | `primary-container` |
| `onPrimaryContainer` | `#561700` | `on-primary-container` |
| `primaryFixed` | `#ffdbcf` | `primary-fixed` |
| `onPrimaryFixed` | `#390c00` | `on-primary-fixed` |
| `primaryFixedDim` | `#ffb59c` | `primary-fixed-dim` |
| `onPrimaryFixedVariant` | `#832700` | `on-primary-fixed-variant` |
| `inversePrimary` | `#ffb59c` | `inverse-primary` |
| `secondary` | `#2559bd` | `secondary` (Pathfinder Blue) |
| `onSecondary` | `#ffffff` | `on-secondary` |
| `secondaryContainer` | `#6c98ff` | `secondary-container` |
| `onSecondaryContainer` | `#002f76` | `on-secondary-container` |
| `secondaryFixed` | `#dae2ff` | `secondary-fixed` |
| `onSecondaryFixed` | `#001946` | `on-secondary-fixed` |
| `secondaryFixedDim` | `#b1c5ff` | `secondary-fixed-dim` |
| `onSecondaryFixedVariant` | `#00419e` | `on-secondary-fixed-variant` |
| `tertiary` | `#006493` | `tertiary` |
| `onTertiary` | `#ffffff` | `on-tertiary` |
| `tertiaryContainer` | `#009de4` | `tertiary-container` |
| `onTertiaryContainer` | `#00304a` | `on-tertiary-container` |
| `tertiaryFixed` | `#cae6ff` | `tertiary-fixed` |
| `onTertiaryFixed` | `#001e30` | `on-tertiary-fixed` |
| `tertiaryFixedDim` | `#8dcdff` | `tertiary-fixed-dim` |
| `onTertiaryFixedVariant` | `#004b70` | `on-tertiary-fixed-variant` |
| `error` | `#ba1a1a` | `error` |
| `onError` | `#ffffff` | `on-error` |
| `errorContainer` | `#ffdad6` | `error-container` |
| `onErrorContainer` | `#93000a` | `on-error-container` |
| `surface` | `#f9f9fc` | `surface` (= `background`) |
| `onSurface` | `#1a1c1e` | `on-surface` |
| `surfaceDim` | `#dadadc` | `surface-dim` |
| `surfaceBright` | `#f9f9fc` | `surface-bright` |
| `surfaceContainerLowest` | `#ffffff` | `surface-container-lowest` |
| `surfaceContainerLow` | `#f3f3f6` | `surface-container-low` |
| `surfaceContainer` | `#eeeef0` | `surface-container` |
| `surfaceContainerHigh` | `#e8e8ea` | `surface-container-high` |
| `surfaceContainerHighest` | `#e2e2e5` | `surface-container-highest` |
| `surfaceVariant` | `#e2e2e5` | `surface-variant` |
| `onSurfaceVariant` | `#5b4138` | `on-surface-variant` |
| `inverseSurface` | `#2f3133` | `inverse-surface` |
| `inverseOnSurface` | `#f0f0f3` | `inverse-on-surface` |
| `outline` | `#8f7066` | `outline` |
| `outlineVariant` | `#e3bfb3` | `outline-variant` |
| `surfaceTint` | `#ab3600` | `surface-tint` |
| `shadow` | `#000000` | (default) |
| `scrim` | `#000000` | (default) |
| `background` | `#f9f9fc` | `background` |
| `onBackground` | `#1a1c1e` | `on-background` |

### 1.2 Dark mode

The Stitch HTML uses `darkMode: "class"` and ships hand-rolled `dark:`
utilities (slate / orange) instead of an extended dark palette. So a
proper Material 3 dark `ColorScheme` is **derived** in
`apps/mobile/lib/core/theme/app_colors.dart` rather than extracted from
HTML.

Derivation rules (standard Material 3 dark conventions over the locked
light palette):

| Role | Dark value | Why |
| --- | --- | --- |
| `primary` | `#ffb59c` | Lightened Safety Orange (= light's `primaryFixedDim`) |
| `onPrimary` | `#561700` | Was `onPrimaryContainer` in light |
| `primaryContainer` | `#832700` | Was `onPrimaryFixedVariant` in light |
| `onPrimaryContainer` | `#ffdbcf` | Was `primaryFixed` in light |
| `secondary` | `#b1c5ff` | Lightened Pathfinder Blue (= `secondaryFixedDim`) |
| `onSecondary` | `#002f76` | Was `onSecondaryContainer` |
| `secondaryContainer` | `#00419e` | Was `onSecondaryFixedVariant` |
| `onSecondaryContainer` | `#dae2ff` | Was `secondaryFixed` |
| `tertiary` | `#8dcdff` | Was `tertiaryFixedDim` |
| `onTertiary` | `#00304a` | Was `onTertiaryContainer` |
| `tertiaryContainer` | `#004b70` | Was `onTertiaryFixedVariant` |
| `onTertiaryContainer` | `#cae6ff` | Was `tertiaryFixed` |
| `error` | `#ffb4ab` | M3 dark error |
| `onError` | `#690005` | M3 dark on-error |
| `errorContainer` | `#93000a` | Was `onErrorContainer` in light |
| `onErrorContainer` | `#ffdad6` | Was `errorContainer` in light |
| `surface` | `#111315` | M3 dark surface (~10% L) |
| `onSurface` | `#e2e2e5` | Was `surfaceContainerHighest` |
| `surfaceDim` | `#111315` | Same as surface |
| `surfaceBright` | `#37393b` | M3 dark surface-bright |
| `surfaceContainerLowest` | `#0c0e10` | M3 dark surface-container-lowest |
| `surfaceContainerLow` | `#1a1c1e` | Was `onSurface` in light (inverted) |
| `surfaceContainer` | `#1e2022` | M3 dark surface-container |
| `surfaceContainerHigh` | `#282a2c` | M3 dark surface-container-high |
| `surfaceContainerHighest` | `#333537` | M3 dark surface-container-highest |
| `surfaceVariant` | `#5b4138` | Was `onSurfaceVariant` in light |
| `onSurfaceVariant` | `#e3bfb3` | Was `outlineVariant` in light |
| `inverseSurface` | `#e2e2e5` | Inverted |
| `inverseOnSurface` | `#2f3133` | Inverted |
| `outline` | `#a89089` | M3 dark outline |
| `outlineVariant` | `#5b4138` | Was `onSurfaceVariant` in light |
| `surfaceTint` | `#ffb59c` | Tracks dark `primary` |
| `shadow` | `#000000` | (default) |
| `scrim` | `#000000` | (default) |
| `background` | `#111315` | Same as `surface` |
| `onBackground` | `#e2e2e5` | Same as `onSurface` |
| `inversePrimary` | `#ab3600` | The light primary |

---

## 2. Typography

### 2.1 Font families

| Use | Family | Weight range |
| --- | --- | --- |
| Display, headline | **Space Grotesk** | 300–700 |
| Title, body, label | **Inter** | 300–700 (radar map view loads 100–900) |

Loaded via `google_fonts: ^6.2.1` in Flutter.

### 2.2 Type scale (Material 3)

Stitch HTML doesn't ship explicit M3 sizes — it uses Tailwind classes
(`text-3xl`, `text-6xl`, etc.). The Flutter theme applies the standard
**Material 3 type scale** with the Kinetic Path family swap:

| Role | Family | Size | Weight | Line height | Letter spacing |
| --- | --- | --- | --- | --- | --- |
| `displayLarge` | Space Grotesk | 57 | 400 | 64 | -0.25 |
| `displayMedium` | Space Grotesk | 45 | 400 | 52 | 0 |
| `displaySmall` | Space Grotesk | 36 | 400 | 44 | 0 |
| `headlineLarge` | Space Grotesk | 32 | 700 | 40 | 0 |
| `headlineMedium` | Space Grotesk | 28 | 700 | 36 | 0 |
| `headlineSmall` | Space Grotesk | 24 | 700 | 32 | 0 |
| `titleLarge` | Inter | 22 | 600 | 28 | 0 |
| `titleMedium` | Inter | 16 | 600 | 24 | 0.15 |
| `titleSmall` | Inter | 14 | 600 | 20 | 0.1 |
| `bodyLarge` | Inter | 16 | 400 | 24 | 0.5 |
| `bodyMedium` | Inter | 14 | 400 | 20 | 0.25 |
| `bodySmall` | Inter | 12 | 400 | 16 | 0.4 |
| `labelLarge` | Inter | 14 | 600 | 20 | 0.1 |
| `labelMedium` | Inter | 12 | 600 | 16 | 0.5 |
| `labelSmall` | Inter | 11 | 600 | 16 | 0.5 |

**Hierarchy as Brand:** display sizes are sparing — `display-lg` is for
landing screens only. Technical / GPS data uses `label-sm` in all-caps
with widely-spaced tracking (replicate via `letterSpacing: 1.5`).

---

## 3. Spacing

Tailwind defaults are used in Stitch HTML — `p-3`, `p-6`, `p-8`, `gap-4`,
`gap-6`, `mb-12`, `mt-2`, `mt-12`. The Flutter spacing scale doubles
Tailwind values to dp:

| Token | Value (dp) |
| --- | --- |
| `xs` | 4 |
| `sm` | 8 |
| `md` | 12 |
| `base` | 16 |
| `lg` | 24 |
| `xl` | 32 |
| `xxl` | 48 |
| `xxxl` | 64 |

---

## 4. Border radii

**These are intentional Kinetic Path values — tighter than Material 3
defaults** to telegraph "rugged precision."

| Token | Stitch CSS | Flutter (dp) |
| --- | --- | --- |
| `DEFAULT` | `0.125rem` | 2 |
| `lg` | `0.25rem` | 4 |
| `xl` | `0.5rem` | 8 |
| `full` | `0.75rem` | 12 |
| `round` | n/a | 999 (pill / circle) |

The `xl` (8dp) is the **standard container rounding** per
`DESIGN_SYSTEM.md` §2 and §7.

---

## 5. Elevation / shadow

Per `DESIGN_SYSTEM.md` §4 (Tonal Layering), traditional drop shadows are
**banned**. Depth comes from stacked `surface-container-*` tiers.

When a floating element is genuinely required (Quick-Action Button, FAB),
use:

```dart
BoxShadow(
  offset: Offset(0, 8),
  blurRadius: 24,
  color: onSurface.withValues(alpha: 0.06),
)
```

Tinted with `onSurface` at 6% opacity. **Never `Colors.black`**.

---

## 6. Glassmorphism recipe

Per `DESIGN_SYSTEM.md` §2 ("Glass & Gradient" Rule), every floating map
overlay must use:

```dart
BackdropFilter(
  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
  child: Container(
    decoration: BoxDecoration(
      color: surfaceContainerLowest.withValues(alpha: 0.85),
      borderRadius: AppRadii.xl, // 8dp
    ),
    child: ...,
  ),
)
```

Exposed via `KineticPathTokens.glassmorphismDecoration()`.

---

## 7. CTA gradient recipe

Verbatim from `designs/onboarding/code.html` lines 83–85:

```css
background: linear-gradient(135deg, #ab3600 0%, #ff5f1f 100%);
```

In Flutter:

```dart
LinearGradient(
  colors: [Color(0xFFAB3600), Color(0xFFFF5F1F)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,  // ≈ 135°
)
```

Exposed via `KineticPathTokens.ctaGradient`.

Per `DESIGN_SYSTEM.md` §5, primary CTAs use this gradient + `xl`
roundedness (8dp) + no border, with the shadow recipe above
(`y-8 blur-24` tinted) for the floating ones.

---

## 8. The No-Line Rule

Per `DESIGN_SYSTEM.md` §2: 1px solid borders are **strictly prohibited**
for sectioning. Boundaries are created through background shifts
(`surface` → `surface-container-low` → `surface-container`).

Component-theme implications enforced in `app_theme.dart`:

- `DividerThemeData(color: Colors.transparent, space: 0)` — kill the
  default Material divider
- `CardTheme(elevation: 0, color: surfaceContainerLow)` — depth via
  background, not shadows
- `InputDecorationTheme` uses `filled: true` + `surfaceContainer` instead
  of an underlined / outlined border for sectioning
- `Divider`, `VerticalDivider`, `Border` widgets must not appear in
  feature code (lint enforcement is a Phase 4 follow-up)

The "Ghost Border" fallback (`outline-variant` at 15% opacity) is allowed
when a map element genuinely needs more definition.

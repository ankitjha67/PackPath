import 'package:flutter/material.dart';

/// PackPath Material 3 color palette — extracted from Stitch Tailwind
/// configs into [designs/DESIGN_TOKENS.md] §1, then transcribed here as
/// the single source of truth for the Flutter app.
///
/// Light values are verbatim from `designs/onboarding/code.html`.
/// Dark values are derived per the rules in DESIGN_TOKENS.md §1.2 — the
/// Stitch HTML uses hand-rolled `dark:` utilities, not an extended dark
/// palette, so a proper M3 dark scheme had to be assembled by hand.
class AppColors {
  AppColors._();

  static const ColorScheme light = ColorScheme(
    brightness: Brightness.light,
    // Primary — Safety Orange
    primary: Color(0xFFAB3600),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFFF5F1F),
    onPrimaryContainer: Color(0xFF561700),
    primaryFixed: Color(0xFFFFDBCF),
    onPrimaryFixed: Color(0xFF390C00),
    primaryFixedDim: Color(0xFFFFB59C),
    onPrimaryFixedVariant: Color(0xFF832700),
    inversePrimary: Color(0xFFFFB59C),
    // Secondary — Pathfinder Blue
    secondary: Color(0xFF2559BD),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFF6C98FF),
    onSecondaryContainer: Color(0xFF002F76),
    secondaryFixed: Color(0xFFDAE2FF),
    onSecondaryFixed: Color(0xFF001946),
    secondaryFixedDim: Color(0xFFB1C5FF),
    onSecondaryFixedVariant: Color(0xFF00419E),
    // Tertiary
    tertiary: Color(0xFF006493),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFF009DE4),
    onTertiaryContainer: Color(0xFF00304A),
    tertiaryFixed: Color(0xFFCAE6FF),
    onTertiaryFixed: Color(0xFF001E30),
    tertiaryFixedDim: Color(0xFF8DCDFF),
    onTertiaryFixedVariant: Color(0xFF004B70),
    // Error
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF93000A),
    // Surface tiers — the No-Line Rule lives here
    surface: Color(0xFFF9F9FC),
    onSurface: Color(0xFF1A1C1E),
    surfaceDim: Color(0xFFDADADC),
    surfaceBright: Color(0xFFF9F9FC),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF3F3F6),
    surfaceContainer: Color(0xFFEEEEF0),
    surfaceContainerHigh: Color(0xFFE8E8EA),
    surfaceContainerHighest: Color(0xFFE2E2E5),
    onSurfaceVariant: Color(0xFF5B4138),
    inverseSurface: Color(0xFF2F3133),
    onInverseSurface: Color(0xFFF0F0F3),
    outline: Color(0xFF8F7066),
    outlineVariant: Color(0xFFE3BFB3),
    surfaceTint: Color(0xFFAB3600),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  static const ColorScheme dark = ColorScheme(
    brightness: Brightness.dark,
    // Primary — lightened Safety Orange
    primary: Color(0xFFFFB59C),
    onPrimary: Color(0xFF561700),
    primaryContainer: Color(0xFF832700),
    onPrimaryContainer: Color(0xFFFFDBCF),
    primaryFixed: Color(0xFFFFDBCF),
    onPrimaryFixed: Color(0xFF390C00),
    primaryFixedDim: Color(0xFFFFB59C),
    onPrimaryFixedVariant: Color(0xFF832700),
    inversePrimary: Color(0xFFAB3600),
    // Secondary — lightened Pathfinder Blue
    secondary: Color(0xFFB1C5FF),
    onSecondary: Color(0xFF002F76),
    secondaryContainer: Color(0xFF00419E),
    onSecondaryContainer: Color(0xFFDAE2FF),
    secondaryFixed: Color(0xFFDAE2FF),
    onSecondaryFixed: Color(0xFF001946),
    secondaryFixedDim: Color(0xFFB1C5FF),
    onSecondaryFixedVariant: Color(0xFF00419E),
    // Tertiary
    tertiary: Color(0xFF8DCDFF),
    onTertiary: Color(0xFF00304A),
    tertiaryContainer: Color(0xFF004B70),
    onTertiaryContainer: Color(0xFFCAE6FF),
    tertiaryFixed: Color(0xFFCAE6FF),
    onTertiaryFixed: Color(0xFF001E30),
    tertiaryFixedDim: Color(0xFF8DCDFF),
    onTertiaryFixedVariant: Color(0xFF004B70),
    // Error
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    // Surface tiers
    surface: Color(0xFF111315),
    onSurface: Color(0xFFE2E2E5),
    surfaceDim: Color(0xFF111315),
    surfaceBright: Color(0xFF37393B),
    surfaceContainerLowest: Color(0xFF0C0E10),
    surfaceContainerLow: Color(0xFF1A1C1E),
    surfaceContainer: Color(0xFF1E2022),
    surfaceContainerHigh: Color(0xFF282A2C),
    surfaceContainerHighest: Color(0xFF333537),
    onSurfaceVariant: Color(0xFFE3BFB3),
    inverseSurface: Color(0xFFE2E2E5),
    onInverseSurface: Color(0xFF2F3133),
    outline: Color(0xFFA89089),
    outlineVariant: Color(0xFF5B4138),
    surfaceTint: Color(0xFFFFB59C),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );
}

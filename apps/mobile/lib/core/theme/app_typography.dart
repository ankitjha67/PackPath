import 'package:flutter/material.dart';

import 'app_colors.dart';

/// PackPath type scale per [designs/DESIGN_TOKENS.md] §2.
///
/// Material 3 sizes with the Kinetic Path family swap:
/// - Display + headline: **Space Grotesk**
/// - Title + body + label: **Inter**
///
/// Both families are bundled as variable TTFs in `fonts/` and declared
/// in `pubspec.yaml`. We do **not** use `google_fonts` — version 6.x
/// trips a `dart:ui` const-evaluation bug on Flutter 3.22.3 because
/// `FontWeight` lacks a primitive `==` operator. See the commit message
/// of `fix(theme): bundle fonts locally, replace google_fonts package`
/// for the full diagnosis.
class AppTypography {
  AppTypography._();

  static const String _displayFamily = 'SpaceGrotesk';
  static const String _bodyFamily = 'Inter';

  static TextTheme textTheme(Brightness brightness) {
    final color = brightness == Brightness.light
        ? AppColors.light.onSurface
        : AppColors.dark.onSurface;

    TextStyle headline(
      double size,
      FontWeight weight,
      double height, {
      double letterSpacing = 0,
    }) =>
        TextStyle(
          fontFamily: _displayFamily,
          fontSize: size,
          fontWeight: weight,
          height: height / size,
          letterSpacing: letterSpacing,
          color: color,
        );

    TextStyle body(
      double size,
      FontWeight weight,
      double height, {
      double letterSpacing = 0,
    }) =>
        TextStyle(
          fontFamily: _bodyFamily,
          fontSize: size,
          fontWeight: weight,
          height: height / size,
          letterSpacing: letterSpacing,
          color: color,
        );

    return TextTheme(
      // Display — Space Grotesk
      displayLarge: headline(57, FontWeight.w400, 64, letterSpacing: -0.25),
      displayMedium: headline(45, FontWeight.w400, 52),
      displaySmall: headline(36, FontWeight.w400, 44),
      // Headline — Space Grotesk, bold
      headlineLarge: headline(32, FontWeight.w700, 40),
      headlineMedium: headline(28, FontWeight.w700, 36),
      headlineSmall: headline(24, FontWeight.w700, 32),
      // Title — Inter, semibold
      titleLarge: body(22, FontWeight.w600, 28),
      titleMedium: body(16, FontWeight.w600, 24, letterSpacing: 0.15),
      titleSmall: body(14, FontWeight.w600, 20, letterSpacing: 0.1),
      // Body — Inter
      bodyLarge: body(16, FontWeight.w400, 24, letterSpacing: 0.5),
      bodyMedium: body(14, FontWeight.w400, 20, letterSpacing: 0.25),
      bodySmall: body(12, FontWeight.w400, 16, letterSpacing: 0.4),
      // Label — Inter, semibold
      labelLarge: body(14, FontWeight.w600, 20, letterSpacing: 0.1),
      labelMedium: body(12, FontWeight.w600, 16, letterSpacing: 0.5),
      labelSmall: body(11, FontWeight.w600, 16, letterSpacing: 0.5),
    );
  }

  /// Per `DESIGN_SYSTEM.md` §3 — technical / GPS data uses `label-sm` in
  /// all-caps with widely-spaced tracking. Apply this on top of
  /// `labelSmall` when rendering coordinates, timestamps, ids.
  static const TextStyle technicalLabel = TextStyle(
    fontFamily: _bodyFamily,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.5,
    height: 16 / 11,
  );
}

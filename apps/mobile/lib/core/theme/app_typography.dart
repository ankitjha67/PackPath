import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// PackPath type scale per [designs/DESIGN_TOKENS.md] §2.
///
/// Material 3 sizes with the Kinetic Path family swap:
/// - Display + headline: **Space Grotesk**
/// - Title + body + label: **Inter**
class AppTypography {
  AppTypography._();

  static TextTheme textTheme(Brightness brightness) {
    final color = brightness == Brightness.light
        ? AppColors.light.onSurface
        : AppColors.dark.onSurface;

    TextStyle headline(double size, FontWeight weight, double height,
            {double letterSpacing = 0}) =>
        GoogleFonts.spaceGrotesk(
          fontSize: size,
          fontWeight: weight,
          height: height / size,
          letterSpacing: letterSpacing,
          color: color,
        );

    TextStyle body(double size, FontWeight weight, double height,
            {double letterSpacing = 0}) =>
        GoogleFonts.inter(
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
    fontFamily: 'Inter',
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.5,
    height: 16 / 11,
  );
}

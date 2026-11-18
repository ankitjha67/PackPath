import 'package:flutter/material.dart';

/// PackPath Material 3 colour palette.
///
/// Built from **Sanzo Wada combination 250** of *A Dictionary of Color
/// Combinations* (1933): Pyrite Yellow, Peach Red, Sea Green, Nile Blue.
/// The app leads with the bright **Sea Green** teal (#25AC91) as the brand
/// primary, with muted **Pyrite Yellow** gold (#D4AE3A) as the secondary and
/// vivid **Peach Red** (#F34F20) as the tertiary accent; pale **Nile Blue**
/// (#D2EBED) tints containers. Schemes are generated with Material 3 tonal
/// palettes from these key colours so every on-/container token keeps its
/// contrast in both light and dark.
class AppColors {
  AppColors._();

  /// Wada combination 250 members used as Material key colours.
  static const Color seaGreen = Color(0xFF25AC91); // 100 — primary / brand
  static const Color pyrite = Color(0xFFD4AE3A); //  58 — secondary (gold)
  static const Color peachRed =
      Color(0xFFF34F20); //  65 — tertiary / warm accent
  static const Color nileBlue = Color(0xFFD2EBED); // 111 — pale container tint

  static final ColorScheme light = ColorScheme.fromSeed(
    seedColor: seaGreen,
    brightness: Brightness.light,
    secondary: pyrite,
    tertiary: peachRed,
  );

  static final ColorScheme dark = ColorScheme.fromSeed(
    seedColor: seaGreen,
    brightness: Brightness.dark,
    secondary: pyrite,
    tertiary: peachRed,
  );
}

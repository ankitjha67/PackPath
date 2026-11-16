import 'package:flutter/material.dart';

/// PackPath Material 3 colour palette.
///
/// Built from **Sanzo Wada combination 293** of *A Dictionary of Color
/// Combinations* (1933): Raw Sienna, Turquoise Green, Artemisia Green, Green.
/// The app leads with the forest **Green** (#4E8F5C) as the brand primary,
/// with **Artemisia sage** (#879D9A) as the secondary and warm **Raw Sienna**
/// (#C36B1D) as the tertiary accent. Schemes are generated with Material 3
/// tonal palettes from these key colours so every on-/container token keeps
/// its contrast in both light and dark.
class AppColors {
  AppColors._();

  /// Wada combination 293 members used as Material key colours.
  static const Color green = Color(0xFF4E8F5C); // 103 — primary / brand
  static const Color sage = Color(0xFF879D9A); // 95  — secondary
  static const Color sienna = Color(0xFFC36B1D); // 14  — tertiary / warm accent
  static const Color turquoise = Color(0xFFC3E3D6); // 88 — pale container tint

  static final ColorScheme light = ColorScheme.fromSeed(
    seedColor: green,
    brightness: Brightness.light,
    secondary: sage,
    tertiary: sienna,
  );

  static final ColorScheme dark = ColorScheme.fromSeed(
    seedColor: green,
    brightness: Brightness.dark,
    secondary: sage,
    tertiary: sienna,
  );
}

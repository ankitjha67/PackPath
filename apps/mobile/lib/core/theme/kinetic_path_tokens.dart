import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_radii.dart';

/// Custom design tokens beyond what Material 3's `ColorScheme` /
/// `TextTheme` cover. Per [designs/DESIGN_TOKENS.md] §6 and §7.
///
/// Access via:
/// ```dart
/// final tokens = Theme.of(context).extension<KineticPathTokens>()!;
/// ```
@immutable
class KineticPathTokens extends ThemeExtension<KineticPathTokens> {
  const KineticPathTokens({
    required this.ctaGradient,
    required this.glassmorphismBase,
    required this.glassmorphismBlur,
    required this.glassmorphismOpacity,
    required this.floatingShadowColor,
  });

  /// Primary CTA gradient — `primary` → `primary_container` at ~135°.
  /// Per `designs/onboarding/code.html` line 84:
  /// `linear-gradient(135deg, #ab3600 0%, #ff5f1f 100%)`
  final LinearGradient ctaGradient;

  /// Base color for glassmorphism overlays. Mix with [glassmorphismOpacity]
  /// inside a [BackdropFilter] of [glassmorphismBlur] sigma.
  final Color glassmorphismBase;

  /// Backdrop blur sigma in dp. Per `DESIGN_SYSTEM.md` §2 — locked at 12.
  final double glassmorphismBlur;

  /// Opacity of [glassmorphismBase] when stacked over the map. Locked at 0.85.
  final double glassmorphismOpacity;

  /// Tinted shadow color for floating elements (FABs, PTT button, SOS).
  /// Per `DESIGN_SYSTEM.md` §4 — never `Colors.black`, always tinted at
  /// ~6% opacity over `onSurface`.
  final Color floatingShadowColor;

  /// Build a `BoxDecoration` ready to drop inside a `BackdropFilter`-wrapped
  /// container. Standard Kinetic Path glassmorphism overlay.
  BoxDecoration glassmorphismDecoration({BorderRadius? borderRadius}) {
    return BoxDecoration(
      color: glassmorphismBase.withValues(alpha: glassmorphismOpacity),
      borderRadius: borderRadius ?? AppRadii.xl,
    );
  }

  /// Standard floating-element shadow per `DESIGN_SYSTEM.md` §4:
  /// `y-8, blur-24, on-surface @ 6%`.
  List<BoxShadow> get floatingShadow => [
        BoxShadow(
          offset: const Offset(0, 8),
          blurRadius: 24,
          color: floatingShadowColor,
        ),
      ];

  /// Wrap a child in a `BackdropFilter` + glassmorphism container in one call.
  Widget glassmorphismOverlay({
    required Widget child,
    BorderRadius? borderRadius,
    EdgeInsetsGeometry? padding,
  }) {
    final radius = borderRadius ?? AppRadii.xl;
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
            sigmaX: glassmorphismBlur, sigmaY: glassmorphismBlur),
        child: Container(
          padding: padding,
          decoration: glassmorphismDecoration(borderRadius: radius),
          child: child,
        ),
      ),
    );
  }

  static const KineticPathTokens light = KineticPathTokens(
    ctaGradient: LinearGradient(
      colors: [Color(0xFFAB3600), Color(0xFFFF5F1F)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    glassmorphismBase: Color(0xFFFFFFFF),
    glassmorphismBlur: 12,
    glassmorphismOpacity: 0.85,
    floatingShadowColor: Color(0x0F1A1C1E), // ~6% on-surface
  );

  static const KineticPathTokens dark = KineticPathTokens(
    ctaGradient: LinearGradient(
      colors: [Color(0xFFAB3600), Color(0xFFFF5F1F)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    glassmorphismBase: Color(0xFF1A1C1E),
    glassmorphismBlur: 12,
    glassmorphismOpacity: 0.85,
    floatingShadowColor: Color(0x14000000),
  );

  @override
  KineticPathTokens copyWith({
    LinearGradient? ctaGradient,
    Color? glassmorphismBase,
    double? glassmorphismBlur,
    double? glassmorphismOpacity,
    Color? floatingShadowColor,
  }) {
    return KineticPathTokens(
      ctaGradient: ctaGradient ?? this.ctaGradient,
      glassmorphismBase: glassmorphismBase ?? this.glassmorphismBase,
      glassmorphismBlur: glassmorphismBlur ?? this.glassmorphismBlur,
      glassmorphismOpacity: glassmorphismOpacity ?? this.glassmorphismOpacity,
      floatingShadowColor: floatingShadowColor ?? this.floatingShadowColor,
    );
  }

  @override
  KineticPathTokens lerp(ThemeExtension<KineticPathTokens>? other, double t) {
    if (other is! KineticPathTokens) return this;
    return KineticPathTokens(
      ctaGradient: LinearGradient.lerp(ctaGradient, other.ctaGradient, t)!,
      glassmorphismBase:
          Color.lerp(glassmorphismBase, other.glassmorphismBase, t)!,
      glassmorphismBlur:
          lerpDouble(glassmorphismBlur, other.glassmorphismBlur, t)!,
      glassmorphismOpacity:
          lerpDouble(glassmorphismOpacity, other.glassmorphismOpacity, t)!,
      floatingShadowColor:
          Color.lerp(floatingShadowColor, other.floatingShadowColor, t)!,
    );
  }
}

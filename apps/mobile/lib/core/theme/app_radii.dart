import 'package:flutter/material.dart';

/// PackPath border radii per [designs/DESIGN_TOKENS.md] §4.
///
/// **Intentionally tighter than Material 3 defaults.** The Stitch
/// Tailwind config sets `xl` to `0.5rem` (8dp) — the Kinetic Path
/// "Precision Utility" voice avoids the soft, pillowy corners that
/// signal "consumer app" and instead uses crisper rounding to telegraph
/// "rugged precision".
class AppRadii {
  AppRadii._();

  /// 2dp — `DEFAULT` in Stitch Tailwind config
  static const Radius _xs = Radius.circular(2);
  static const Radius _lg = Radius.circular(4);
  static const Radius _xl = Radius.circular(8);
  static const Radius _full = Radius.circular(12);
  static const Radius _round = Radius.circular(999);

  static const BorderRadius xs = BorderRadius.all(_xs);

  /// 4dp — `lg` in Stitch
  static const BorderRadius lg = BorderRadius.all(_lg);

  /// 8dp — `xl` in Stitch. **Standard container rounding** per
  /// `DESIGN_SYSTEM.md` §7.
  static const BorderRadius xl = BorderRadius.all(_xl);

  /// 12dp — `full` in Stitch (NOT a circle — Kinetic Path's "full" is
  /// generous-but-not-pill).
  static const BorderRadius full = BorderRadius.all(_full);

  /// True circular / pill — for FABs, avatars, status dots.
  static const BorderRadius round = BorderRadius.all(_round);
}

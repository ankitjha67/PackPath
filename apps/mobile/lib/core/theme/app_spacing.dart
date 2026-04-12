/// PackPath spacing scale per [designs/DESIGN_TOKENS.md] §3.
///
/// Stitch HTML uses raw Tailwind classes (`p-3`, `p-6`, `p-8`,
/// `gap-4`, `mb-12`); these constants are the dp equivalents that
/// Flutter widgets should reference instead of hardcoding magic numbers.
class AppSpacing {
  AppSpacing._();

  /// 4dp — used inside dense layouts (chip padding, tight gaps)
  static const double xs = 4;

  /// 8dp — small gaps, icon-text spacing
  static const double sm = 8;

  /// 12dp — section padding inside cards
  static const double md = 12;

  /// 16dp — base unit, default container padding
  static const double base = 16;

  /// 24dp — large vertical rhythm, section spacing
  static const double lg = 24;

  /// 32dp — major section breaks
  static const double xl = 32;

  /// 48dp — page-level dividers
  static const double xxl = 48;

  /// 64dp — hero spacing
  static const double xxxl = 64;
}

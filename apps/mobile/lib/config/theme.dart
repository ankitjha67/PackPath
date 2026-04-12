// DEPRECATED: Use lib/core/theme/app_theme.dart instead.
//
// Kept temporarily so any straggler imports from before the design
// system extraction don't break the build. Delete in Session 3 once
// every screen has been migrated to AppTheme.
//
// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

@Deprecated(
  'Use AppTheme.light / AppTheme.dark from lib/core/theme/app_theme.dart',
)
class PackPathTheme {
  @Deprecated('Use AppTheme.light')
  static ThemeData light() => AppTheme.light;

  @Deprecated('Use AppTheme.dark')
  static ThemeData dark() => AppTheme.dark;
}

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radii.dart';
import 'app_spacing.dart';
import 'app_typography.dart';
import 'kinetic_path_tokens.dart';

/// PackPath theme entry point. Composes the Kinetic Path color palette,
/// type scale, spacing, and custom tokens into a single Material 3
/// `ThemeData` for both light and dark modes.
///
/// Component themes here enforce the **No-Line Rule** from
/// `designs/DESIGN_SYSTEM.md` §2 — no Material dividers, no outlined
/// borders for sectioning. Boundaries come from surface-container shifts.
class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(
        colorScheme: AppColors.light,
        tokens: KineticPathTokens.light,
        brightness: Brightness.light,
      );

  static ThemeData get dark => _build(
        colorScheme: AppColors.dark,
        tokens: KineticPathTokens.dark,
        brightness: Brightness.dark,
      );

  static ThemeData _build({
    required ColorScheme colorScheme,
    required KineticPathTokens tokens,
    required Brightness brightness,
  }) {
    final textTheme = AppTypography.textTheme(brightness);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: colorScheme.surface,
      canvasColor: colorScheme.surface,
      extensions: [tokens],

      // No-Line Rule: kill the default Material divider entirely.
      dividerTheme: const DividerThemeData(
        color: Colors.transparent,
        space: 0,
        thickness: 0,
      ),
      dividerColor: Colors.transparent,

      // App bar — flat, no shadow, on `surface`.
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),

      // Cards — surface-container-low, no border, no elevation, xl rounding.
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.xl),
        clipBehavior: Clip.antiAlias,
      ),

      // Bottom sheets — surface-container, xl top corners.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        elevation: 0,
        modalBackgroundColor: colorScheme.surfaceContainer,
        modalElevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        showDragHandle: true,
        dragHandleColor: colorScheme.outlineVariant,
      ),

      // Filled buttons — primary CTAs not on the gradient pattern still
      // get the right rounding + typography.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          textStyle: textTheme.labelLarge,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.xl),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: textTheme.labelLarge,
          side: BorderSide(color: colorScheme.outlineVariant, width: 1),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.xl),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: textTheme.labelLarge,
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.xl),
        ),
      ),

      // Inputs — filled (no underline / outline borders for sectioning),
      // surface-container background, no border focus ring.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        hintStyle:
            textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        labelStyle:
            textTheme.labelLarge?.copyWith(color: colorScheme.onSurfaceVariant),
        border: const OutlineInputBorder(
          borderRadius: AppRadii.xl,
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: AppRadii.xl,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.xl,
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadii.xl,
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
      ),

      // Chips — surface-container-high unselected, secondary selected.
      // No border per the No-Line Rule.
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        selectedColor: colorScheme.secondary,
        labelStyle:
            textTheme.labelMedium?.copyWith(color: colorScheme.onSurface),
        secondaryLabelStyle:
            textTheme.labelMedium?.copyWith(color: colorScheme.onSecondary),
        side: BorderSide.none,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.full),
      ),

      // FAB — uses surface-container-lowest with a tinted shadow per
      // DESIGN_SYSTEM §5 (Quick-Action). Real CTA gradient FABs build a
      // custom widget; this is the default for utility FABs.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.surfaceContainerLowest,
        foregroundColor: colorScheme.secondary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.round),
      ),

      // Snack bars — surface-container-highest, no border.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle:
            textTheme.bodyMedium?.copyWith(color: colorScheme.onInverseSurface),
        actionTextColor: colorScheme.inversePrimary,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.xl),
      ),

      // List tile — surface-container-low rows, no separators.
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        iconColor: colorScheme.onSurfaceVariant,
        textColor: colorScheme.onSurface,
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle:
            textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.xs,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.xl),
      ),

      // Page transitions — Material default
      pageTransitionsTheme: const PageTransitionsTheme(),
    );
  }
}

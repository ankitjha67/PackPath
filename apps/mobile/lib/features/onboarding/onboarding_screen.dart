import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/kinetic_path_tokens.dart';

/// PackPath onboarding — first-launch single-screen Bento card stack
/// matching `designs/onboarding/screen.png` and the layout intent in
/// `designs/onboarding/code.html`.
///
/// On mobile the Stitch design collapses the desktop bento grid to a
/// single column: header + 3 pillar cards + privacy block + footer CTA.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  /// SharedPreferences key. Once set to `true`, the router skips this
  /// screen on subsequent launches.
  static const onboardingSeenKey = 'pp.onboarding_seen';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ─── Header branding ────────────────────────────
              Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.sm,
                  bottom: AppSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PackPath',
                      style: text.headlineLarge?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.2,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'THE KINETIC PATH',
                      style: AppTypography.technicalLabel.copyWith(
                        color: colors.secondary,
                      ),
                    ),
                  ],
                ),
              ),

              // ─── Pillar 01 — Live Tracking (large card) ────
              _PillarCard(
                pillarLabel: 'PILLAR 01',
                title: 'Live Tracking',
                body: 'Precision telemetry for every ascent. Real-time pace, '
                    'altitude, and environmental metrics designed for '
                    'high-glare environments.',
                icon: Icons.my_location,
                background: colors.surfaceContainerLowest,
                titleColor: colors.onSurface,
                bodyColor: colors.onSurfaceVariant,
                accentColor: colors.primary,
                pillarLabelBackground: colors.primary.withValues(alpha: 0.10),
                pillarLabelColor: colors.primary,
                minHeight: 220,
                large: true,
              ),
              const SizedBox(height: AppSpacing.base),

              // ─── Pillar 02 — Shared Routes (Pathfinder Blue) ─
              _PillarCard(
                pillarLabel: 'PILLAR 02',
                title: 'Shared Routes',
                body: 'Crowdsourced trail intelligence. Download maps for '
                    'offline survival and contribute new waypoints to the '
                    'collective atlas.',
                icon: Icons.route,
                background: colors.secondary,
                titleColor: colors.onSecondary,
                bodyColor: colors.secondaryFixed,
                accentColor: colors.onSecondary,
                pillarLabelBackground: Colors.white.withValues(alpha: 0.10),
                pillarLabelColor: colors.onSecondary,
              ),
              const SizedBox(height: AppSpacing.base),

              // ─── Pillar 03 — Group Comms ───────────────────
              _PillarCard(
                pillarLabel: 'PILLAR 03',
                title: 'Group Comms',
                body: 'Never lose the pack. Integrated mesh-ready signaling '
                    'and low-bandwidth status updates keep your team '
                    'synchronized in the field.',
                icon: Icons.hub,
                background: colors.surfaceContainerHigh,
                titleColor: colors.onSurface,
                bodyColor: colors.onSurfaceVariant,
                accentColor: colors.tertiary,
                pillarLabelBackground: colors.tertiary.withValues(alpha: 0.10),
                pillarLabelColor: colors.tertiary,
              ),
              const SizedBox(height: AppSpacing.base),

              // ─── Privacy block ─────────────────────────────
              _PrivacyBlock(
                onLocationTap: () => _markSeenAndGo(context, '/login'),
              ),

              const SizedBox(height: AppSpacing.xl),

              // ─── Footer ────────────────────────────────────
              _Footer(
                onPrimary: () => _markSeenAndGo(context, '/login'),
                onSecondary: () => _markSeenAndGo(context, '/login'),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _markSeenAndGo(BuildContext context, String route) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(onboardingSeenKey, true);
    if (!context.mounted) return;
    context.go(route);
  }
}

// ────────────────────────────────────────────────────────────────────────

class _PillarCard extends StatelessWidget {
  const _PillarCard({
    required this.pillarLabel,
    required this.title,
    required this.body,
    required this.icon,
    required this.background,
    required this.titleColor,
    required this.bodyColor,
    required this.accentColor,
    required this.pillarLabelBackground,
    required this.pillarLabelColor,
    this.minHeight = 180,
    this.large = false,
  });

  final String pillarLabel;
  final String title;
  final String body;
  final IconData icon;
  final Color background;
  final Color titleColor;
  final Color bodyColor;
  final Color accentColor;
  final Color pillarLabelBackground;
  final Color pillarLabelColor;
  final double minHeight;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadii.xl,
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: accentColor, size: large ? 44 : 36),
              _PillarBadge(
                label: pillarLabel,
                background: pillarLabelBackground,
                color: pillarLabelColor,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            title,
            style: (large ? text.headlineMedium : text.headlineSmall)?.copyWith(
              color: titleColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            body,
            style: text.bodyMedium?.copyWith(color: bodyColor, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _PillarBadge extends StatelessWidget {
  const _PillarBadge({
    required this.label,
    required this.background,
    required this.color,
  });

  final String label;
  final Color background;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadii.round,
      ),
      child: Text(
        label,
        style: AppTypography.technicalLabel.copyWith(
          color: color,
          fontSize: 10,
          letterSpacing: 1.8,
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────

class _PrivacyBlock extends StatelessWidget {
  const _PrivacyBlock({required this.onLocationTap});

  final VoidCallback onLocationTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: AppRadii.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.security, color: colors.primary, size: 24),
              const SizedBox(width: AppSpacing.md),
              Text(
                'Privacy-First Precision',
                style: text.titleLarge?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'We require location access to power our wayfinding. Your data '
            'is encrypted, processed locally, and never shared with '
            'third-party trackers. You are always in control of your '
            'broadcast signal.',
            style: text.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: onLocationTap,
            icon: const Icon(Icons.location_on, size: 18),
            label: const Text('Grant Location Access'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.primary,
              backgroundColor: colors.surfaceContainerLowest,
              side: BorderSide(color: colors.outlineVariant, width: 1),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer({required this.onPrimary, required this.onSecondary});

  final VoidCallback onPrimary;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<KineticPathTokens>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'READY FOR THE FIELD?',
          style: AppTypography.technicalLabel.copyWith(
            color: colors.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '"Precision utility for the modern adventurer."',
          style: text.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // Primary CTA — Kinetic Path gradient pill
        _GradientCtaButton(
          label: 'Get Started',
          gradient: tokens.ctaGradient,
          shadow: tokens.floatingShadow,
          onPressed: onPrimary,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: onSecondary,
          style: TextButton.styleFrom(
            foregroundColor: colors.onSurfaceVariant,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          ),
          child: Text(
            'Sign In',
            style: text.titleMedium?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _GradientCtaButton extends StatelessWidget {
  const _GradientCtaButton({
    required this.label,
    required this.gradient,
    required this.shadow,
    required this.onPressed,
  });

  final String label;
  final LinearGradient gradient;
  final List<BoxShadow> shadow;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: AppRadii.xl,
          boxShadow: shadow,
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: AppRadii.xl,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.base + 2,
            ),
            child: Center(
              child: Text(
                label,
                style: text.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

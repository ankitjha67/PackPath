import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../auth/auth_repository.dart';
import '../profile/me_repository.dart';

/// App-wide settings hub.
///
/// Every "buried" menu item from the trip_list / trip_map popup
/// kebabs used to live here unreachable-by-deep-link. Now they are
/// first-class rows grouped into Account / Trip data / About.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meAsync = ref.watch(meProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          const _SectionHeader(label: 'ACCOUNT'),
          _SettingsGroup(
            children: [
              _SettingsRow(
                leading: const Icon(Icons.person_outline),
                title: 'Profile',
                subtitle: meAsync.maybeWhen(
                  data: (m) => m.displayName?.isNotEmpty == true
                      ? m.displayName
                      : m.phone,
                  orElse: () => null,
                ),
                onTap: () => context.push('/me'),
              ),
              _SettingsRow(
                leading: Icon(
                  Icons.logout,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: 'Sign out',
                titleColor: Theme.of(context).colorScheme.error,
                onTap: () => _confirmSignOut(context, ref),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const _SectionHeader(label: 'TRIP DATA'),
          _SettingsGroup(
            children: [
              _SettingsRow(
                leading: const Icon(Icons.query_stats),
                title: 'Your stats',
                subtitle: 'Distance, top speed, carbon footprint',
                onTap: () => context.push('/me/stats'),
              ),
              _SettingsRow(
                leading: const Icon(Icons.shield_outlined),
                title: 'Privacy',
                subtitle: 'What we store, when we delete it',
                onTap: () => context.push('/privacy'),
              ),
              _SettingsRow(
                leading: const Icon(Icons.fact_check_outlined),
                title: 'Audit log',
                subtitle: 'Who queried your location',
                onTap: () => context.push('/audit'),
              ),
              _SettingsRow(
                leading: const Icon(Icons.workspace_premium_outlined),
                title: 'Plans',
                subtitle: 'Free, Pro, Family',
                onTap: () => context.push('/plans'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const _SectionHeader(label: 'ABOUT'),
          const _SettingsGroup(
            children: [
              _SettingsRow(
                leading: Icon(Icons.info_outline),
                title: 'Version',
                // TODO(session4): read from package_info_plus once added.
                trailingText: '0.1.0',
                enabled: false,
              ),
              _SettingsRow(
                leading: Icon(Icons.description_outlined),
                title: 'Terms of service',
                trailingText: 'Coming in Session 5',
                enabled: false,
              ),
              _SettingsRow(
                leading: Icon(Icons.policy_outlined),
                title: 'Privacy policy',
                trailingText: 'Coming in Session 5',
                enabled: false,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You will need to request a new OTP to sign back in. '
          'Trip history stays on our servers.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.onError,
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final repo = await ref.read(authRepositoryProvider.future);
      await repo.logout();
      if (!context.mounted) return;
      context.go('/login');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not sign out: $e')),
      );
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.primary,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: AppRadii.lg,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                indent: AppSpacing.lg + AppSpacing.sm,
                color: scheme.surfaceContainerHighest,
              ),
          ],
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailingText,
    this.titleColor,
    this.onTap,
    this.enabled = true,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final Color? titleColor;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            IconTheme(
              data: IconThemeData(
                color: enabled ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
              child: leading,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: textTheme.titleSmall?.copyWith(
                      color: titleColor ??
                          (enabled
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant),
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (trailingText != null)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: Text(
                  trailingText!,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (onTap != null && enabled)
              Icon(
                Icons.chevron_right,
                color: scheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

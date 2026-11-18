import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import 'entitlements_repository.dart';

/// Phase 10 — PackPath Pro overview. Shows the current plan, what each feature
/// unlocks, and an upgrade CTA (records intent; the real charge is handled by
/// the payment provider's webhook).
class ProScreen extends ConsumerWidget {
  const ProScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(entitlementsProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('PackPath Pro')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
        data: (ent) {
          final features = <(String, String, bool)>[
            (
              'Bigger packs',
              'Up to ${ent.maxTripMembers} members per trip',
              ent.maxTripMembers > 5
            ),
            (
              'Offline map tiles',
              'Download routes for no-signal zones',
              ent.offlineTiles
            ),
            (
              'Route & calendar export',
              'GPX and .ics downloads',
              ent.routeExports
            ),
            (
              'Advanced weather',
              'Full route-ahead forecasting',
              ent.advancedWeather
            ),
            ('Priority support', 'Jump the queue', ent.prioritySupport),
          ];
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.base),
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [scheme.primary, scheme.tertiary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: AppRadii.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.workspace_premium,
                          color: Colors.white,
                          size: 28,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          ent.isPro
                              ? 'You\'re on ${ent.plan[0].toUpperCase()}${ent.plan.substring(1)}'
                              : 'Free plan',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ent.isPro
                          ? 'Thanks for supporting PackPath.'
                          : 'Upgrade to unlock the pack\'s full toolkit.',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final f in features)
                ListTile(
                  leading: Icon(
                    f.$3 ? Icons.check_circle : Icons.lock_outline,
                    color: f.$3 ? Colors.green : scheme.onSurfaceVariant,
                  ),
                  title: Text(f.$1),
                  subtitle: Text(f.$2),
                ),
              if (!ent.isPro) ...[
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  onPressed: () => _upgrade(context, ref),
                  icon: const Icon(Icons.workspace_premium),
                  label: const Text('Upgrade to Pro — ₹149/mo'),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Payment is handled securely by our provider. Your plan '
                  'activates once payment is confirmed.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _upgrade(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(proRepositoryProvider.future);
      await repo.recordUpgradeIntent('pro', 'pro_screen');
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Upgrade started — complete payment to activate Pro. '
            '(Payment provider not yet configured in this build.)',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not start: $e')));
    }
  }
}

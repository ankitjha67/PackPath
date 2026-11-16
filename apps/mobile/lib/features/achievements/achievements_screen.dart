import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import 'achievements_repository.dart';

/// Phase 7 — personal achievements. A grid of badges earned from real activity
/// (distance, places rated, hazards reported, chat, checklist, trips), with
/// locked badges showing progress toward the next unlock.
class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badgesAsync = ref.watch(myBadgesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Achievements')),
      body: badgesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 40),
                const SizedBox(height: AppSpacing.sm),
                Text('Could not load achievements: $e',
                    textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(myBadgesProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (badges) {
          final earned = badges.where((b) => b.earned).length;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Row(
                  children: [
                    Text('$earned / ${badges.length} unlocked',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    Icon(Icons.emoji_events,
                        color: Theme.of(context).colorScheme.primary),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: AppSpacing.sm,
                    crossAxisSpacing: AppSpacing.sm,
                    childAspectRatio: 1.15,
                  ),
                  itemCount: badges.length,
                  itemBuilder: (_, i) => _BadgeCard(badge: badges[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BadgeCard extends StatelessWidget {
  const _BadgeCard({required this.badge});
  final BadgeDto badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final earned = badge.earned;
    return Opacity(
      opacity: earned ? 1 : 0.55,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color:
              earned ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: AppRadii.lg,
          border: earned ? Border.all(color: scheme.primary, width: 1.5) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(badge.emoji, style: const TextStyle(fontSize: 30)),
                const Spacer(),
                if (earned)
                  Icon(Icons.verified, color: scheme.primary, size: 20)
                else
                  Icon(Icons.lock_outline,
                      color: scheme.onSurfaceVariant, size: 18),
              ],
            ),
            const Spacer(),
            Text(badge.label,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              badge.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (!earned && badge.goal > 1) ...[
              const SizedBox(height: AppSpacing.xs),
              ClipRRect(
                borderRadius: AppRadii.xs,
                child: LinearProgressIndicator(
                  value: badge.fraction,
                  minHeight: 4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${badge.progress.toStringAsFixed(0)} / '
                '${badge.goal.toStringAsFixed(0)}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

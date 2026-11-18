import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../shared/widgets/user_avatar.dart';
import '../preferences/preferences_repository.dart';
import 'achievements_repository.dart';

/// Phase 7 — the per-trip leaderboard. Ranks members by a blended score of
/// distance covered, chat activity, and hazards reported. Shown as a sheet
/// from the map overflow menu.
class LeaderboardSheet extends ConsumerWidget {
  const LeaderboardSheet({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tripLeaderboardProvider(tripId));
    final prefs = effectivePreferences(ref);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.leaderboard),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Pack leaderboard',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () =>
                      ref.invalidate(tripLeaderboardProvider(tripId)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Points = km + 0.5 × messages + 5 × hazards reported',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: AppSpacing.sm),
            async.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text('Could not load leaderboard: $e'),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: Text('No members yet.'),
                  );
                }
                return Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: rows.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.xs),
                    itemBuilder: (_, i) => _LeaderTile(
                      rank: i + 1,
                      row: rows[i],
                      distanceLabel: prefs.formatDistance(rows[i].distanceKm),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaderTile extends StatelessWidget {
  const _LeaderTile({
    required this.rank,
    required this.row,
    required this.distanceLabel,
  });
  final int rank;
  final LeaderRowDto row;
  final String distanceLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final medal = switch (rank) {
      1 => '🥇',
      2 => '🥈',
      3 => '🥉',
      _ => '$rank',
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: rank <= 3 ? scheme.primaryContainer : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              medal,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          UserAvatar(
            name: row.name ?? 'Member',
            avatarUrl: row.avatarUrl,
            radius: 16,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  row.name ?? 'Member',
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$distanceLabel · '
                  '${row.messages} msg · ${row.hazards} hazard'
                  '${row.hazards == 1 ? "" : "s"}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          Text(
            '${row.points.toStringAsFixed(1)} pts',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

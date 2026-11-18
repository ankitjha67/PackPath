import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/models/trip.dart';
import '../../shared/widgets/user_avatar.dart';
import 'trips_repository.dart';
import 'waypoints_repository.dart';

/// Marshall-facing route progress: for each waypoint, how many of the pack
/// have arrived and who is still pending.
class CheckpointsSheet extends ConsumerWidget {
  const CheckpointsSheet({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final progressAsync = ref.watch(waypointProgressProvider(tripId));
    final tripAsync = ref.watch(tripDetailProvider(tripId));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.flag),
                const SizedBox(width: AppSpacing.sm),
                Text('Checkpoints', style: textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: () =>
                      ref.invalidate(waypointProgressProvider(tripId)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Flexible(
              child: progressAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Could not load: $e')),
                data: (stops) {
                  if (stops.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Text(
                        'No waypoints yet. Long-press the map to add stops, '
                        'then track who arrives here.',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  final members =
                      tripAsync.valueOrNull?.members ?? const <TripMemberDto>[];
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: stops.length,
                    itemBuilder: (_, i) => _CheckpointTile(
                      index: i + 1,
                      isLast: i == stops.length - 1,
                      name: stops[i].name,
                      arrived: stops[i].arrivedUserIds,
                      members: members,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckpointTile extends StatelessWidget {
  const _CheckpointTile({
    required this.index,
    required this.isLast,
    required this.name,
    required this.arrived,
    required this.members,
  });

  final int index;
  final bool isLast;
  final String name;
  final Set<String> arrived;
  final List<TripMemberDto> members;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final total = members.length;
    final count = members.where((m) => arrived.contains(m.userId)).length;
    final allHere = total > 0 && count == total;
    final accent = allHere ? const Color(0xFF2ECC71) : scheme.primary;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline rail: node + connector.
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: count > 0 ? accent : scheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: allHere
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : Text(
                        '$index',
                        style: TextStyle(
                          color: count > 0
                              ? Colors.white
                              : scheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: scheme.surfaceContainerHighest,
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(name, style: textTheme.titleSmall),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.15),
                          borderRadius: AppRadii.full,
                        ),
                        child: Text(
                          '$count / $total',
                          style: textTheme.labelMedium?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (count == 0)
                    Text(
                      'No one here yet',
                      style: textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    )
                  else
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final m in members)
                          if (arrived.contains(m.userId))
                            UserAvatar(
                              name: m.label,
                              avatarUrl: m.avatarUrl,
                              radius: 12,
                            ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

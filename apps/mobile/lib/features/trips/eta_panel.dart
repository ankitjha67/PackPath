import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import 'etas_repository.dart';
import 'trips_repository.dart';

/// Bottom sheet that lists each member's ETA to the next waypoint.
/// Empty when no waypoints exist or the Mapbox token isn't configured.
class EtaPanel extends ConsumerWidget {
  const EtaPanel({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etasAsync = ref.watch(tripEtasProvider(tripId));
    final tripAsync = ref.watch(tripDetailProvider(tripId));
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final memberColors = tripAsync.maybeWhen(
      data: (trip) => {for (final m in trip.members) m.userId: m.color},
      orElse: () => const <String, String>{},
    );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.45,
      minChildSize: 0.25,
      maxChildSize: 0.85,
      builder: (context, scrollController) => Material(
        color: scheme.surfaceContainer,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(8),
            topRight: Radius.circular(8),
          ),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.base,
            AppSpacing.md,
            AppSpacing.base,
            AppSpacing.base,
          ),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              'ETA to next stop',
              style: textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            etasAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
              data: (etas) {
                if (etas.members.isEmpty) {
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    child: Text(
                      etas.waypointName == null
                          ? 'Add a waypoint to see ETAs.'
                          : 'No live positions yet for ${etas.waypointName}.',
                      style: textTheme.bodyMedium,
                    ),
                  );
                }
                return Column(
                  children: [
                    if (etas.waypointName != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: Text(
                            'Heading to ${etas.waypointName}',
                            style: textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    for (final m in etas.members) ...[
                      Container(
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: AppRadii.lg,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.md,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: _hex(
                                  memberColors[m.userId] ?? '#888888',
                                ),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    m.userId.substring(0, 8),
                                    style: textTheme.titleSmall,
                                  ),
                                  Text(
                                    '${(m.distanceM / 1000).toStringAsFixed(1)} km',
                                    style: textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              _formatDuration(m.durationS),
                              style: textTheme.headlineSmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: TextButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
                onPressed: () => ref.invalidate(tripEtasProvider(tripId)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(double seconds) {
    final m = (seconds / 60).round();
    if (m < 60) return '$m min';
    final h = m ~/ 60;
    final rem = m % 60;
    return '${h}h ${rem}m';
  }

  static Color _hex(String value) {
    final hex = value.replaceAll('#', '');
    final v = int.parse(hex, radix: 16);
    return Color(0xFF000000 | v);
  }
}

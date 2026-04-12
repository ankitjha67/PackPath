import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'etas_repository.dart';

/// Bottom sheet that lists each member's ETA to the next waypoint.
/// Empty when no waypoints exist or the Mapbox token isn't configured.
class EtaPanel extends ConsumerWidget {
  const EtaPanel({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etasAsync = ref.watch(tripEtasProvider(tripId));
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.45,
      minChildSize: 0.25,
      maxChildSize: 0.85,
      builder: (context, scrollController) => Material(
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'ETA to next stop',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            etasAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
              data: (etas) {
                if (etas.members.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      etas.waypointName == null
                          ? 'Add a waypoint to see ETAs.'
                          : 'No live positions yet for ${etas.waypointName}.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  );
                }
                return Column(
                  children: [
                    if (etas.waypointName != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Heading to ${etas.waypointName}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    for (final m in etas.members)
                      ListTile(
                        leading: const Icon(Icons.directions_car_outlined),
                        title: Text('Member ${m.userId.substring(0, 6)}'),
                        subtitle: Text(
                          '${(m.distanceM / 1000).toStringAsFixed(1)} km',
                        ),
                        trailing: Text(
                          _formatDuration(m.durationS),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
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
}

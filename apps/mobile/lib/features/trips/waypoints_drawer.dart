import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'waypoints_repository.dart';

/// Bottom sheet listing every waypoint on the trip with delete support.
/// (Reordering will use ReorderableListView once the backend grows a
/// bulk-reorder endpoint — for v1, delete + re-add is enough.)
class WaypointsDrawer extends ConsumerWidget {
  const WaypointsDrawer({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waypointsAsync = ref.watch(tripWaypointsProvider(tripId));
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.25,
      maxChildSize: 0.9,
      builder: (context, scroll) => Material(
        child: Column(
          children: [
            const SizedBox(height: 8),
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
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    'Waypoints',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  Text(
                    'Long-press the map to add',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Expanded(
              child: waypointsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (waypoints) {
                  if (waypoints.isEmpty) {
                    return const Center(child: Text('No waypoints yet'));
                  }
                  return ListView.builder(
                    controller: scroll,
                    itemCount: waypoints.length,
                    itemBuilder: (_, i) {
                      final w = waypoints[i];
                      return Dismissible(
                        key: ValueKey(w.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.redAccent,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) async {
                          final repo = await ref
                              .read(waypointsRepositoryProvider.future);
                          await repo.delete(
                              tripId: tripId, waypointId: w.id);
                          ref.invalidate(tripWaypointsProvider(tripId));
                          ref.invalidate(tripRouteProvider(tripId));
                        },
                        child: ListTile(
                          leading: CircleAvatar(child: Text('${i + 1}')),
                          title: Text(w.name),
                          subtitle: Text(
                            '${w.lat.toStringAsFixed(4)}, '
                            '${w.lng.toStringAsFixed(4)}',
                          ),
                        ),
                      );
                    },
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

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../config/env.dart';
import '../map/live_trip_controller.dart';
import 'eta_panel.dart';
import 'trips_repository.dart';
import 'waypoints_drawer.dart';
import 'waypoints_repository.dart';

/// Live group map for a single trip. Wires the WebSocket fan-out to
/// `flutter_map` markers, plus waypoint long-press to add and a polyline
/// fetched from the backend Mapbox Directions proxy.
class TripMapScreen extends ConsumerWidget {
  const TripMapScreen({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripAsync = ref.watch(tripDetailProvider(tripId));
    final live = ref.watch(liveTripProvider(tripId));
    final waypointsAsync = ref.watch(tripWaypointsProvider(tripId));
    final routeAsync = ref.watch(tripRouteProvider(tripId));

    final waypoints = waypointsAsync.maybeWhen(
      data: (w) => w,
      orElse: () => const [],
    );

    return Scaffold(
      appBar: AppBar(
        title: tripAsync.maybeWhen(
          data: (t) => Text(t.name),
          orElse: () => const Text('Trip'),
        ),
        actions: [
          IconButton(
            tooltip: 'Chat',
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => context.push('/trips/$tripId/chat'),
          ),
          IconButton(
            tooltip: 'Invite',
            icon: const Icon(Icons.qr_code_2),
            onPressed: () => context.push('/trips/$tripId/share'),
          ),
          IconButton(
            tooltip: 'Waypoints',
            icon: const Icon(Icons.flag_outlined),
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => WaypointsDrawer(tripId: tripId),
            ),
          ),
          IconButton(
            tooltip: 'ETA',
            icon: const Icon(Icons.access_time),
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => EtaPanel(tripId: tripId),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  live.connected ? Icons.cloud_done : Icons.cloud_off,
                  color:
                      live.connected ? Colors.greenAccent : Colors.redAccent,
                ),
                if (live.queuedFrames > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${live.queuedFrames}',
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: const LatLng(28.6139, 77.2090),
              initialZoom: 12,
              onLongPress: (_, point) =>
                  _onLongPress(context, ref, point, waypoints.length),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    '${Env.mapboxStyleUrl}?access_token=${Env.mapboxPublicToken}',
                userAgentPackageName: 'app.packpath.mobile',
                maxZoom: 19,
              ),
              // Routed polyline (preferred), else straight line between
              // waypoints if the directions proxy is unavailable.
              routeAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => _StraightLine(waypoints),
                data: (route) => route == null
                    ? _StraightLine(waypoints)
                    : PolylineLayer(
                        polylines: [
                          Polyline(
                            points: route.points,
                            color: Colors.blueAccent,
                            strokeWidth: 5,
                          ),
                        ],
                      ),
              ),
              MarkerLayer(
                markers: [
                  for (var i = 0; i < waypoints.length; i++)
                    Marker(
                      point: waypoints[i].latLng,
                      width: 36,
                      height: 36,
                      child: _WaypointPin(index: i + 1),
                    ),
                  for (final m in live.members.values)
                    Marker(
                      point: m.position,
                      width: 44,
                      height: 44,
                      child: _MemberDot(
                        color: _colorForUser(m.userId, tripAsync),
                        battery: m.battery,
                      ),
                    ),
                ],
              ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© Mapbox'),
                  TextSourceAttribution('© OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: tripAsync.when(
                  loading: () => const SizedBox(
                    height: 36,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Text('Error: $e'),
                  data: (trip) => Row(
                    children: [
                      const Icon(Icons.group, size: 18),
                      const SizedBox(width: 8),
                      Text('${trip.members.length} in pack'),
                      const SizedBox(width: 16),
                      const Icon(Icons.flag_outlined, size: 18),
                      const SizedBox(width: 4),
                      Text('${waypoints.length}'),
                      const Spacer(),
                      Text('Code ${trip.joinCode}'),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: IgnorePointer(
              child: Card(
                color: Colors.black54,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  child: Text(
                    'Long-press the map to add a waypoint',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onLongPress(
    BuildContext context,
    WidgetRef ref,
    LatLng point,
    int currentCount,
  ) async {
    final controller = TextEditingController(text: 'Stop ${currentCount + 1}');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add waypoint'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      final repo = await ref.read(waypointsRepositoryProvider.future);
      await repo.add(
        tripId: tripId,
        name: name,
        lat: point.latitude,
        lng: point.longitude,
        position: currentCount,
      );
      ref.invalidate(tripWaypointsProvider(tripId));
      ref.invalidate(tripRouteProvider(tripId));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add waypoint: $e')),
        );
      }
    }
  }

  Color _colorForUser(String userId, AsyncValue tripAsync) {
    return tripAsync.maybeWhen(
      data: (trip) {
        final m = (trip.members as List).cast<dynamic>().firstWhere(
              (e) => e.userId == userId,
              orElse: () => null,
            );
        if (m == null) return Colors.blue;
        return _hex(m.color as String);
      },
      orElse: () => Colors.blue,
    );
  }

  static Color _hex(String value) {
    final hex = value.replaceAll('#', '');
    final v = int.parse(hex, radix: 16);
    return Color(0xFF000000 | v);
  }
}

class _StraightLine extends StatelessWidget {
  const _StraightLine(this.waypoints);
  final List waypoints;

  @override
  Widget build(BuildContext context) {
    if (waypoints.length < 2) return const SizedBox.shrink();
    return PolylineLayer(
      polylines: [
        Polyline(
          points: [for (final w in waypoints) w.latLng as LatLng],
          color: Colors.blueAccent.withOpacity(0.5),
          strokeWidth: 4,
          pattern: const StrokePattern.dashed(segments: [10, 6]),
        ),
      ],
    );
  }
}

class _WaypointPin extends StatelessWidget {
  const _WaypointPin({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.deepOrange,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        '$index',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _MemberDot extends StatelessWidget {
  const _MemberDot({required this.color, this.battery});

  final Color color;
  final int? battery;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(blurRadius: 4, color: Colors.black26),
            ],
          ),
        ),
        if (battery != null)
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$battery%',
                style: const TextStyle(color: Colors.white, fontSize: 9),
              ),
            ),
          ),
      ],
    );
  }
}

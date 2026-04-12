import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../config/env.dart';
import '../map/live_trip_controller.dart';
import 'trips_repository.dart';

/// Live group map for a single trip. Wires the WebSocket fan-out to
/// `flutter_map` markers, one per member.
class TripMapScreen extends ConsumerWidget {
  const TripMapScreen({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripAsync = ref.watch(tripDetailProvider(tripId));
    final live = ref.watch(liveTripProvider(tripId));

    return Scaffold(
      appBar: AppBar(
        title: tripAsync.maybeWhen(
          data: (t) => Text(t.name),
          orElse: () => const Text('Trip'),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(
              live.connected ? Icons.cloud_done : Icons.cloud_off,
              color: live.connected ? Colors.greenAccent : Colors.redAccent,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(28.6139, 77.2090),
              initialZoom: 12,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    '${Env.mapboxStyleUrl}?access_token=${Env.mapboxPublicToken}',
                userAgentPackageName: 'app.packpath.mobile',
                maxZoom: 19,
              ),
              MarkerLayer(
                markers: [
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
                      const Spacer(),
                      Text('Code ${trip.joinCode}'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_client.dart';
import '../../shared/models/waypoint.dart';

class WaypointsRepository {
  WaypointsRepository(this.dio);

  final Dio dio;

  Future<List<WaypointDto>> list(String tripId) async {
    final response = await dio.get('/trips/$tripId/waypoints');
    return (response.data as List)
        .map((w) => WaypointDto.fromJson(w as Map<String, dynamic>))
        .toList();
  }

  Future<WaypointDto> add({
    required String tripId,
    required String name,
    required double lat,
    required double lng,
    required int position,
    int arrivalRadiusM = 150,
  }) async {
    final response = await dio.post(
      '/trips/$tripId/waypoints',
      data: {
        'name': name,
        'lat': lat,
        'lng': lng,
        'position': position,
        'arrival_radius_m': arrivalRadiusM,
      },
    );
    return WaypointDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> delete({required String tripId, required String waypointId}) =>
      dio.delete('/trips/$tripId/waypoints/$waypointId');

  /// Hits the backend Mapbox directions proxy. The Mapbox token never leaves
  /// the server, and the route is automatically scoped to trip members.
  Future<RouteGeometry?> directions({
    required String tripId,
    required List<LatLng> coordinates,
    String profile = 'driving',
  }) async {
    if (coordinates.length < 2) return null;
    final response = await dio.post(
      '/trips/$tripId/directions',
      data: {
        'profile': profile,
        'coordinates': [
          for (final c in coordinates) {'lat': c.latitude, 'lng': c.longitude},
        ],
      },
    );
    final data = response.data as Map<String, dynamic>;
    final geom = data['geometry'] as Map<String, dynamic>;
    final coords = (geom['coordinates'] as List)
        .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
        .toList();
    return RouteGeometry(
      points: coords,
      distanceM: (data['distance_m'] as num).toDouble(),
      durationS: (data['duration_s'] as num).toDouble(),
    );
  }
}

final waypointsRepositoryProvider = FutureProvider<WaypointsRepository>((
  ref,
) async {
  final dio = await ref.watch(apiClientProvider.future);
  return WaypointsRepository(dio);
});

final tripWaypointsProvider = FutureProvider.family<List<WaypointDto>, String>((
  ref,
  tripId,
) async {
  final repo = await ref.watch(waypointsRepositoryProvider.future);
  return repo.list(tripId);
});

/// Cached route polyline for the current waypoint sequence. Recomputed
/// whenever the waypoint list for the trip changes.
final tripRouteProvider = FutureProvider.family<RouteGeometry?, String>((
  ref,
  tripId,
) async {
  final waypoints = await ref.watch(tripWaypointsProvider(tripId).future);
  if (waypoints.length < 2) return null;
  final repo = await ref.watch(waypointsRepositoryProvider.future);
  try {
    return await repo.directions(
      tripId: tripId,
      coordinates: waypoints.map((w) => w.latLng).toList(),
    );
  } catch (_) {
    // If the proxy isn't configured yet, fall back to a straight-line render.
    return null;
  }
});

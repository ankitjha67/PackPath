import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_client.dart';
import '../../shared/models/waypoint.dart';

/// Progress at one waypoint: who has arrived (and when).
class WaypointProgress {
  const WaypointProgress({
    required this.waypointId,
    required this.name,
    required this.arrivedUserIds,
  });

  final String waypointId;
  final String name;
  final Set<String> arrivedUserIds;

  factory WaypointProgress.fromJson(Map<String, dynamic> json) {
    final arrived = (json['arrived'] as List?) ?? const [];
    return WaypointProgress(
      waypointId: json['waypoint_id'] as String,
      name: json['name'] as String,
      arrivedUserIds: {
        for (final a in arrived)
          (a as Map<String, dynamic>)['user_id'] as String,
      },
    );
  }
}

/// Weather at one waypoint along the trip.
class WaypointWeather {
  const WaypointWeather({
    required this.name,
    required this.temperatureC,
    required this.condition,
    required this.windKmh,
    required this.pop,
  });

  final String name;
  final double temperatureC;
  final String condition;
  final double windKmh;
  final double pop; // probability of precipitation, 0..1

  factory WaypointWeather.fromJson(Map<String, dynamic> json) =>
      WaypointWeather(
        name: json['name'] as String? ?? '',
        temperatureC: (json['temperature_c'] as num?)?.toDouble() ?? 0,
        condition: json['condition'] as String? ?? 'Clear',
        windKmh: (json['wind_kmh'] as num?)?.toDouble() ?? 0,
        pop: (json['pop'] as num?)?.toDouble() ?? 0,
      );
}

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

  Future<List<WaypointProgress>> progress(String tripId) async {
    final response = await dio.get('/trips/$tripId/waypoints/progress');
    return (response.data as List)
        .map((w) => WaypointProgress.fromJson(w as Map<String, dynamic>))
        .toList();
  }

  Future<List<WaypointWeather>> weather(String tripId) async {
    final response = await dio.get('/trips/$tripId/waypoints/weather');
    return (response.data as List)
        .map((w) => WaypointWeather.fromJson(w as Map<String, dynamic>))
        .toList();
  }

  /// Weather at arbitrary points (for the live "route ahead" forecast).
  Future<List<WaypointWeather>> weatherAt(
    String tripId,
    List<LatLng> points,
  ) async {
    final response = await dio.post(
      '/trips/$tripId/waypoints/weather/at',
      data: {
        'points': [
          for (final p in points) {'lat': p.latitude, 'lng': p.longitude},
        ],
      },
    );
    return (response.data as List)
        .map((w) => WaypointWeather.fromJson(w as Map<String, dynamic>))
        .toList();
  }

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

  /// Estimate fuel + toll cost for the route through [coordinates] for the
  /// given [vehicle]. Returns null when the route can't be resolved.
  Future<RouteCost?> routeCost({
    required String tripId,
    required List<LatLng> coordinates,
    String vehicle = 'hatchback',
    String region = 'IN',
  }) async {
    if (coordinates.length < 2) return null;
    final response = await dio.post(
      '/trips/$tripId/directions/cost',
      data: {
        'profile': 'driving',
        'region': region,
        'vehicle': vehicle,
        'coordinates': [
          for (final c in coordinates) {'lat': c.latitude, 'lng': c.longitude},
        ],
      },
    );
    final d = response.data as Map<String, dynamic>;
    return RouteCost(
      fuelCents: (d['fuel_cents'] as num?)?.toInt() ?? 0,
      tollCents: (d['toll_cents'] as num?)?.toInt() ?? 0,
      totalCents: (d['total_cents'] as num?)?.toInt() ?? 0,
      fuelLitres: (d['fuel_litres'] as num?)?.toDouble() ?? 0,
      currency: d['currency'] as String? ?? 'INR',
    );
  }
}

class RouteCost {
  const RouteCost({
    required this.fuelCents,
    required this.tollCents,
    required this.totalCents,
    required this.fuelLitres,
    required this.currency,
  });
  final int fuelCents;
  final int tollCents;
  final int totalCents;
  final double fuelLitres;
  final String currency;
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

/// Live forecast for the route ahead. The family key encodes the trip, the
/// member's rounded position and heading ("tripId|lat|lng|bearing"); weather is
/// sampled 10 / 15 / 20 km ahead along that bearing. Keying on rounded values
/// means it refetches as the pack moves, not on every GPS tick.
final routeAheadWeatherProvider =
    FutureProvider.autoDispose.family<List<WaypointWeather>, String>((
  ref,
  key,
) async {
  final parts = key.split('|');
  final tripId = parts[0];
  final origin = LatLng(double.parse(parts[1]), double.parse(parts[2]));
  final bearing = double.parse(parts[3]);
  const distance = Distance();
  final points = [10000.0, 15000.0, 20000.0]
      .map((m) => distance.offset(origin, m, bearing))
      .toList();
  final repo = await ref.watch(waypointsRepositoryProvider.future);
  return repo.weatherAt(tripId, points);
});

/// Weather along the trip's waypoints.
final tripWeatherProvider =
    FutureProvider.autoDispose.family<List<WaypointWeather>, String>((
  ref,
  tripId,
) async {
  final repo = await ref.watch(waypointsRepositoryProvider.future);
  return repo.weather(tripId);
});

/// Per-waypoint arrival progress for a trip (who has reached each stop).
final waypointProgressProvider =
    FutureProvider.autoDispose.family<List<WaypointProgress>, String>((
  ref,
  tripId,
) async {
  final repo = await ref.watch(waypointsRepositoryProvider.future);
  return repo.progress(tripId);
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

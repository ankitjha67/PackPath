import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_client.dart';
import '../../shared/models/waypoint.dart';
import '../trips/waypoints_repository.dart';
import 'hazard_model.dart';

/// HTTP client for the backend /hazards endpoint.
///
/// The backend already caches the EONET fan-out globally for 15 minutes
/// and slices by bbox/categories server-side, so this class is a thin
/// Dio wrapper that swallows upstream failures and returns an empty
/// list rather than throwing. The banner and the map overlay both
/// want "no data" to be silent, not a full-screen error.
class HazardsRepository {
  HazardsRepository(this.dio);

  final Dio dio;

  /// Fetch hazards in the given bbox, optionally filtered by category.
  ///
  /// [bbox] is `[south, west, north, east]` in degrees, matching the
  /// server contract. Returns an empty list on any upstream failure —
  /// the polling loop will try again on the next tick and the UI stays
  /// quiet in the meantime.
  Future<List<HazardDto>> fetch({
    List<double>? bbox,
    List<String>? categories,
  }) async {
    final params = <String, String>{};
    if (bbox != null && bbox.length == 4) {
      params['bbox'] = bbox.join(',');
    }
    if (categories != null && categories.isNotEmpty) {
      params['categories'] = categories.join(',');
    }
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/hazards',
        queryParameters: params,
      );
      final data = response.data;
      if (data == null) return const [];
      final rows = (data['hazards'] as List?) ?? const [];
      final hazards = <HazardDto>[];
      for (final row in rows) {
        try {
          hazards.add(HazardDto.fromJson(row as Map<String, dynamic>));
        } catch (_) {
          // Drop malformed rows, keep the rest. Better to surface 19
          // hazards than error on 1.
        }
      }
      return hazards;
    } on DioException catch (_) {
      return const [];
    } catch (_) {
      return const [];
    }
  }
}

final hazardsRepositoryProvider = FutureProvider<HazardsRepository>((
  ref,
) async {
  final dio = await ref.watch(apiClientProvider.future);
  return HazardsRepository(dio);
});

/// Approx 1° of latitude ≈ 111 km at the equator. We pad the waypoint
/// bbox by ~1° in each direction (~111 km) so hazards just outside the
/// exact route envelope still show up as context on the map.
const double _bboxPadDegrees = 1.0;

List<double>? _bboxFromWaypoints(List<WaypointDto> waypoints) {
  if (waypoints.isEmpty) return null;
  double south = waypoints.first.lat;
  double north = waypoints.first.lat;
  double west = waypoints.first.lng;
  double east = waypoints.first.lng;
  for (final w in waypoints) {
    if (w.lat < south) south = w.lat;
    if (w.lat > north) north = w.lat;
    if (w.lng < west) west = w.lng;
    if (w.lng > east) east = w.lng;
  }
  south = (south - _bboxPadDegrees).clamp(-90.0, 90.0);
  north = (north + _bboxPadDegrees).clamp(-90.0, 90.0);
  west = (west - _bboxPadDegrees).clamp(-180.0, 180.0);
  east = (east + _bboxPadDegrees).clamp(-180.0, 180.0);
  return [south, west, north, east];
}

/// Public trip hazards provider. Computes a padded bbox from the
/// trip's waypoints, fetches once on subscribe, and sets up a
/// Timer.periodic that invalidates the provider every 5 minutes so
/// Riverpod re-runs it. `ref.onDispose(timer.cancel)` tears the timer
/// down when the screen leaves the tree.
///
/// If the trip has no waypoints yet we skip the fetch — there's no
/// region to query — and return an empty list. A later invalidation
/// (once waypoints land) will trigger the first real fetch.
final tripHazardsProvider =
    FutureProvider.family<List<HazardDto>, String>((ref, tripId) async {
  final waypoints = await ref.watch(tripWaypointsProvider(tripId).future);
  if (waypoints.isEmpty) {
    return const <HazardDto>[];
  }
  final bbox = _bboxFromWaypoints(waypoints);
  final repo = await ref.watch(hazardsRepositoryProvider.future);

  // Schedule the next poll 5 minutes out. Invalidating self re-runs
  // this body; `ref.onDispose` ensures the timer doesn't outlive the
  // provider's subscription.
  final timer = Timer.periodic(const Duration(minutes: 5), (_) {
    ref.invalidateSelf();
  });
  ref.onDispose(timer.cancel);

  return repo.fetch(bbox: bbox);
});

/// Pure bbox helper exposed for tests and the proximity widget.
List<double>? debugBboxFromWaypoints(List<WaypointDto> waypoints) =>
    _bboxFromWaypoints(waypoints);

/// Convenience for other files that want the trip's route polyline as
/// `List<LatLng>` — the banner and proximity check both need this and
/// `tripRouteProvider` already parses it into `RouteGeometry.points`,
/// so we just re-export via a helper in the banner.
typedef RoutePoints = List<LatLng>;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'hazard_model.dart';

/// Per-category proximity buffer in kilometres.
///
/// These are **first-pass heuristics** — tuned by intuition, not by
/// real data. A Session 4 task can re-tune them once we have hazard
/// history to grade against.
///
/// Categories mapped to `0.0` are ambient / visual-only and never
/// trigger the proximity banner. They still render as map pins via
/// `HazardLayer` — the buffer only gates the banner.
const _categoryBufferKm = <String, double>{
  'wildfires': 100.0, // smoke plumes travel far, air quality impact
  'severeStorms': 75.0, // weather fronts move fast
  'floods': 50.0, // localized but route-blocking
  'volcanoes': 100.0, // ash plumes
  'landslides': 25.0, // very localized
  'earthquakes': 15.0, // aftershocks are local
  'drought': 0.0, // ambient, never alert
  'dustHaze': 75.0,
  'seaLakeIce': 25.0,
  'manmade': 25.0,
  'snow': 50.0,
  'tempExtremes': 50.0,
  'waterColor': 0.0, // visual only, never block
};

const double _earthRadiusKm = 6371.0;

/// Pair of (hazard, min distance) for sorting and de-duping.
class _HazardDistance {
  _HazardDistance(this.hazard, this.distanceKm);
  final HazardDto hazard;
  final double distanceKm;
}

/// Return hazards whose nearest geometry is within the per-category
/// buffer of the given [route] polyline.
///
/// - Point geometries: haversine distance from each route point,
///   keep the minimum.
/// - Polygon geometries: bbox envelope check first (cheap), then
///   point-in-polygon on the route points against each ring.
///   Distance is 0 if the route intersects the polygon, otherwise
///   haversine to the nearest vertex.
///
/// Hazards in categories with a `0.0` buffer (drought, waterColor)
/// are dropped entirely — they never trigger the banner.
/// The result is distinct by hazard id, sorted ascending by min
/// distance to the route.
List<HazardDto> hazardsNearRoute(
  List<LatLng> route,
  List<HazardDto> hazards,
) {
  if (route.isEmpty || hazards.isEmpty) return const [];

  final out = <_HazardDistance>[];
  for (final hazard in hazards) {
    final buffer = _categoryBufferKm[hazard.category];
    if (buffer == null || buffer <= 0) continue;
    final d = _minDistanceKm(route, hazard.geometries);
    if (d == null) continue;
    if (d <= buffer) {
      out.add(_HazardDistance(hazard, d));
    }
  }

  out.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
  return out.map((e) => e.hazard).toList(growable: false);
}

/// Minimum great-circle distance from [route] to any of the [geometries],
/// in kilometres. Returns null if nothing was measurable.
double? _minDistanceKm(List<LatLng> route, List<GeometryDto> geometries) {
  double? best;
  for (final geometry in geometries) {
    switch (geometry) {
      case PointGeometry(:final lat, :final lng):
        for (final p in route) {
          final d = _haversineKm(p.latitude, p.longitude, lat, lng);
          if (best == null || d < best) best = d;
        }
      case PolygonGeometry(:final rings):
        if (rings.isEmpty) continue;
        final ring = rings.first;
        if (ring.isEmpty) continue;
        final bbox = _ringBbox(ring);
        // Cheap envelope check: if any route point is inside the
        // bbox, fall through to the expensive point-in-polygon
        // check; otherwise just take the min vertex distance.
        final anyInside = route.any(
          (p) =>
              p.latitude >= bbox.south &&
              p.latitude <= bbox.north &&
              p.longitude >= bbox.west &&
              p.longitude <= bbox.east,
        );
        if (anyInside) {
          final hit = route.any((p) => _pointInRing(p, ring));
          if (hit) return 0.0;
        }
        for (final p in route) {
          for (final v in ring) {
            final d = _haversineKm(
              p.latitude,
              p.longitude,
              v.latitude,
              v.longitude,
            );
            if (best == null || d < best) best = d;
          }
        }
    }
  }
  return best;
}

class _RingBbox {
  const _RingBbox(this.south, this.west, this.north, this.east);
  final double south;
  final double west;
  final double north;
  final double east;
}

_RingBbox _ringBbox(List<LatLng> ring) {
  double south = ring.first.latitude;
  double north = ring.first.latitude;
  double west = ring.first.longitude;
  double east = ring.first.longitude;
  for (final p in ring) {
    if (p.latitude < south) south = p.latitude;
    if (p.latitude > north) north = p.latitude;
    if (p.longitude < west) west = p.longitude;
    if (p.longitude > east) east = p.longitude;
  }
  return _RingBbox(south, west, north, east);
}

/// Even-odd ray-cast point-in-polygon test. Walks each edge and
/// flips an inside flag on every crossing of the horizontal ray
/// from the test point.
bool _pointInRing(LatLng point, List<LatLng> ring) {
  bool inside = false;
  final n = ring.length;
  for (var i = 0, j = n - 1; i < n; j = i++) {
    final yi = ring[i].latitude;
    final xi = ring[i].longitude;
    final yj = ring[j].latitude;
    final xj = ring[j].longitude;
    final intersects = ((yi > point.latitude) != (yj > point.latitude)) &&
        (point.longitude <
            (xj - xi) * (point.latitude - yi) / ((yj - yi) + 1e-12) + xi);
    if (intersects) inside = !inside;
  }
  return inside;
}

double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  final dLat = _deg2rad(lat2 - lat1);
  final dLng = _deg2rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_deg2rad(lat1)) *
          math.cos(_deg2rad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return _earthRadiusKm * c;
}

double _deg2rad(double deg) => deg * math.pi / 180.0;

/// Exposed for tests / the banner's severity-count display.
double? proximityBufferForCategory(String category) =>
    _categoryBufferKm[category];

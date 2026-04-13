import 'package:latlong2/latlong.dart';

/// A single geometry attached to a NASA EONET hazard event.
///
/// EONET emits either Points (e.g. earthquake epicentres, active
/// wildfire hotspots) or Polygons (e.g. smoke plumes, iceberg
/// outlines). Coordinates follow GeoJSON convention — Point is
/// `[lng, lat]`, Polygon is a list of linear rings where each
/// ring is a list of `[lng, lat]` pairs.
sealed class GeometryDto {
  const GeometryDto();

  /// Build the right subclass from a JSON map. Returns null on
  /// unknown geometry types instead of throwing so a single bad
  /// row doesn't crash the whole list.
  static GeometryDto? fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    final coords = json['coordinates'];
    if (coords == null) return null;
    switch (type) {
      case 'Point':
        if (coords is! List || coords.length < 2) return null;
        return PointGeometry(
          lng: (coords[0] as num).toDouble(),
          lat: (coords[1] as num).toDouble(),
        );
      case 'Polygon':
        if (coords is! List) return null;
        final rings = <List<LatLng>>[];
        for (final ring in coords) {
          if (ring is! List) continue;
          final ringPoints = <LatLng>[];
          for (final pt in ring) {
            if (pt is! List || pt.length < 2) continue;
            ringPoints.add(
              LatLng((pt[1] as num).toDouble(), (pt[0] as num).toDouble()),
            );
          }
          if (ringPoints.isNotEmpty) rings.add(ringPoints);
        }
        if (rings.isEmpty) return null;
        return PolygonGeometry(rings: rings);
      default:
        return null;
    }
  }

  /// All points touched by this geometry — for a Point, the single
  /// coord; for a Polygon, every ring vertex flattened. Used by the
  /// proximity check and the marker anchor calculation.
  Iterable<LatLng> get points;

  /// A single anchor point for a map marker. For a Polygon this is
  /// the centroid of the outer ring; for a Point it's the coord.
  LatLng get anchor;
}

class PointGeometry extends GeometryDto {
  const PointGeometry({required this.lat, required this.lng});

  final double lat;
  final double lng;

  @override
  Iterable<LatLng> get points => [LatLng(lat, lng)];

  @override
  LatLng get anchor => LatLng(lat, lng);
}

class PolygonGeometry extends GeometryDto {
  const PolygonGeometry({required this.rings});

  /// Outer ring first, then any holes. Matches GeoJSON convention.
  final List<List<LatLng>> rings;

  @override
  Iterable<LatLng> get points sync* {
    for (final ring in rings) {
      yield* ring;
    }
  }

  @override
  LatLng get anchor {
    if (rings.isEmpty || rings.first.isEmpty) {
      return const LatLng(0, 0);
    }
    final ring = rings.first;
    double lat = 0;
    double lng = 0;
    for (final p in ring) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / ring.length, lng / ring.length);
  }
}

/// Normalized hazard event served by GET /hazards.
class HazardDto {
  const HazardDto({
    required this.id,
    required this.title,
    required this.category,
    required this.severity,
    required this.updatedAt,
    required this.geometries,
    this.sourceUrl,
  });

  final String id;
  final String title;

  /// One of: `wildfires`, `severeStorms`, `volcanoes`, `seaLakeIce`,
  /// `earthquakes`, `floods`, `landslides`, `drought`, `dustHaze`,
  /// `manmade`, `snow`, `tempExtremes`, `waterColor`.
  final String category;

  /// `info` | `warning` | `severe`. Inferred server-side.
  final String severity;

  final DateTime updatedAt;
  final List<GeometryDto> geometries;
  final String? sourceUrl;

  factory HazardDto.fromJson(Map<String, dynamic> json) {
    final geoms = <GeometryDto>[];
    for (final g in (json['geometries'] as List? ?? const [])) {
      final parsed = GeometryDto.fromJson(g as Map<String, dynamic>);
      if (parsed != null) geoms.add(parsed);
    }
    return HazardDto(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Unnamed hazard',
      category: json['category'] as String? ?? 'manmade',
      severity: json['severity'] as String? ?? 'info',
      updatedAt: DateTime.parse(json['updated_at'] as String),
      geometries: geoms,
      sourceUrl: json['source_url'] as String?,
    );
  }

  HazardDto copyWith({
    String? id,
    String? title,
    String? category,
    String? severity,
    DateTime? updatedAt,
    List<GeometryDto>? geometries,
    String? sourceUrl,
  }) {
    return HazardDto(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      severity: severity ?? this.severity,
      updatedAt: updatedAt ?? this.updatedAt,
      geometries: geometries ?? this.geometries,
      sourceUrl: sourceUrl ?? this.sourceUrl,
    );
  }
}

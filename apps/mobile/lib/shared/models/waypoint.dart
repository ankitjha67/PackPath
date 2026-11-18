import 'package:latlong2/latlong.dart';

class WaypointDto {
  const WaypointDto({
    required this.id,
    required this.tripId,
    required this.name,
    required this.position,
    required this.lat,
    required this.lng,
    required this.arrivalRadiusM,
    this.category,
    this.notes,
    this.assigneeId,
  });

  final String id;
  final String tripId;
  final String name;
  final int position;
  final double lat;
  final double lng;
  final int arrivalRadiusM;
  final String? category;
  final String? notes;
  final String? assigneeId;

  LatLng get latLng => LatLng(lat, lng);

  factory WaypointDto.fromJson(Map<String, dynamic> json) => WaypointDto(
        id: json['id'] as String,
        tripId: json['trip_id'] as String,
        name: json['name'] as String,
        position: json['position'] as int,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        arrivalRadiusM: json['arrival_radius_m'] as int,
        category: json['category'] as String?,
        notes: json['notes'] as String?,
        assigneeId: json['assignee_id'] as String?,
      );
}

class RouteGeometry {
  const RouteGeometry({
    required this.points,
    required this.distanceM,
    required this.durationS,
  });

  final List<LatLng> points;
  final double distanceM;
  final double durationS;
}

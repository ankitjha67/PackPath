import 'package:latlong2/latlong.dart';

/// Most-recent known position for a single trip member, as observed via the
/// trip WebSocket. Updated in-place when new frames arrive.
class MemberLocation {
  MemberLocation({
    required this.userId,
    required this.position,
    this.heading,
    this.speed,
    this.battery,
    DateTime? lastUpdate,
  }) : lastUpdate = lastUpdate ?? DateTime.now();

  final String userId;
  LatLng position;
  double? heading;
  double? speed;
  int? battery;
  DateTime lastUpdate;
}

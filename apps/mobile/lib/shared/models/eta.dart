class MemberEta {
  const MemberEta({
    required this.userId,
    required this.distanceM,
    required this.durationS,
    required this.targetWaypointId,
    required this.targetWaypointName,
  });

  final String userId;
  final double distanceM;
  final double durationS;
  final String targetWaypointId;
  final String targetWaypointName;

  factory MemberEta.fromJson(Map<String, dynamic> json) => MemberEta(
        userId: json['user_id'] as String,
        distanceM: (json['distance_m'] as num).toDouble(),
        durationS: (json['duration_s'] as num).toDouble(),
        targetWaypointId: json['target_waypoint_id'] as String,
        targetWaypointName: json['target_waypoint_name'] as String,
      );
}

class TripEtas {
  const TripEtas({this.waypointName, required this.members});

  final String? waypointName;
  final List<MemberEta> members;

  factory TripEtas.fromJson(Map<String, dynamic> json) => TripEtas(
        waypointName: json['waypoint_name'] as String?,
        members: ((json['members'] as List?) ?? const [])
            .map((m) => MemberEta.fromJson(m as Map<String, dynamic>))
            .toList(),
      );

  static const empty = TripEtas(waypointName: null, members: []);
}

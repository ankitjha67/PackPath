class TripMemberDto {
  const TripMemberDto({
    required this.userId,
    required this.role,
    required this.color,
    required this.ghostMode,
  });

  final String userId;
  final String role;
  final String color;
  final bool ghostMode;

  factory TripMemberDto.fromJson(Map<String, dynamic> json) => TripMemberDto(
        userId: json['user_id'] as String,
        role: json['role'] as String,
        color: json['color'] as String,
        ghostMode: json['ghost_mode'] as bool? ?? false,
      );
}

class TripDto {
  const TripDto({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.status,
    required this.joinCode,
    required this.members,
    this.startAt,
    this.endAt,
  });

  final String id;
  final String ownerId;
  final String name;
  final String status;
  final String joinCode;
  final List<TripMemberDto> members;
  final DateTime? startAt;
  final DateTime? endAt;

  factory TripDto.fromJson(Map<String, dynamic> json) => TripDto(
        id: json['id'] as String,
        ownerId: json['owner_id'] as String,
        name: json['name'] as String,
        status: json['status'] as String,
        joinCode: json['join_code'] as String,
        startAt: json['start_at'] == null
            ? null
            : DateTime.parse(json['start_at'] as String),
        endAt: json['end_at'] == null
            ? null
            : DateTime.parse(json['end_at'] as String),
        members: ((json['members'] as List?) ?? const [])
            .map((m) => TripMemberDto.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}

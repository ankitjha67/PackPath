class MessageDto {
  const MessageDto({
    required this.id,
    required this.tripId,
    required this.userId,
    required this.body,
    required this.kind,
    required this.sentAt,
  });

  final String id;
  final String tripId;
  final String userId;
  final String body;
  final String kind;
  final DateTime sentAt;

  bool get isSystem => kind != 'text';

  factory MessageDto.fromJson(Map<String, dynamic> json) => MessageDto(
        id: json['id'] as String,
        tripId: json['trip_id'] as String,
        userId: json['user_id'] as String,
        body: json['body'] as String,
        kind: json['kind'] as String,
        sentAt: DateTime.parse(json['sent_at'] as String),
      );
}

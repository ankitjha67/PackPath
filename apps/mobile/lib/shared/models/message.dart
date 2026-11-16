class MessageDto {
  const MessageDto({
    required this.id,
    required this.tripId,
    required this.userId,
    required this.body,
    required this.kind,
    required this.sentAt,
    this.displayName,
    this.avatarUrl,
    this.attachmentKind,
    this.attachmentUrl,
    this.reactions = const {},
    this.myReactions = const {},
  });

  final String id;
  final String tripId;
  final String userId;
  final String body;
  final String kind;
  final DateTime sentAt;
  final String? displayName;
  final String? avatarUrl;

  /// image | video | file | location (null for a plain text message).
  final String? attachmentKind;

  /// For media: a /media/... path. For location: "lat,lng".
  final String? attachmentUrl;

  /// emoji -> count on this message, and the emojis the current user added.
  final Map<String, int> reactions;
  final Set<String> myReactions;

  bool get isSystem => kind != 'text';
  bool get hasAttachment => attachmentKind != null && attachmentUrl != null;

  /// Friendly handle for the sender, falling back to a short id when the
  /// server hasn't minted a name yet.
  String get senderLabel =>
      displayName ?? '${userId.substring(0, userId.length.clamp(0, 6))}…';

  factory MessageDto.fromJson(Map<String, dynamic> json) => MessageDto(
        id: json['id'] as String,
        tripId: json['trip_id'] as String,
        userId: json['user_id'] as String,
        body: json['body'] as String,
        kind: json['kind'] as String,
        sentAt: DateTime.parse(json['sent_at'] as String),
        displayName: json['display_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        attachmentKind: json['attachment_kind'] as String?,
        attachmentUrl: json['attachment_url'] as String?,
        reactions: (json['reactions'] as Map?)?.map(
              (k, v) => MapEntry(k as String, (v as num).toInt()),
            ) ??
            const {},
        myReactions: ((json['my_reactions'] as List?) ?? const [])
            .map((e) => e as String)
            .toSet(),
      );
}

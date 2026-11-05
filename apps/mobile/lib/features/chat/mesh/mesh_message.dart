import 'dart:convert';

/// A chat message as it travels over the Bluetooth/Nearby mesh.
///
/// Carries a client-generated [id] so the same message arriving via multiple
/// paths (a direct peer, a relay hop, and later the server echo on reconnect)
/// can be de-duplicated everywhere by id rather than by content.
class MeshMessage {
  const MeshMessage({
    required this.id,
    required this.tripId,
    required this.senderId,
    required this.body,
    required this.sentAt,
    this.ttl = 4,
  });

  /// Client-generated unique id (also used as the server reconcile key).
  final String id;
  final String tripId;
  final String senderId;
  final String body;
  final DateTime sentAt;

  /// Remaining relay hops. Decremented on each rebroadcast; at 0 the message
  /// is delivered locally but no longer forwarded, bounding mesh flooding.
  final int ttl;

  MeshMessage copyWith({int? ttl}) => MeshMessage(
        id: id,
        tripId: tripId,
        senderId: senderId,
        body: body,
        sentAt: sentAt,
        ttl: ttl ?? this.ttl,
      );

  Map<String, dynamic> toJson() => {
        'v': 1,
        'id': id,
        'trip_id': tripId,
        'sender_id': senderId,
        'body': body,
        'sent_at': sentAt.toUtc().toIso8601String(),
        'ttl': ttl,
      };

  static MeshMessage? tryParse(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['v'] != 1) return null;
      return MeshMessage(
        id: json['id'] as String,
        tripId: json['trip_id'] as String,
        senderId: json['sender_id'] as String,
        body: json['body'] as String,
        sentAt: DateTime.tryParse(json['sent_at'] as String? ?? '')?.toUtc() ??
            DateTime.now().toUtc(),
        ttl: (json['ttl'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode(toJson());
}

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

/// Another member's profile as seen by the current user within a trip.
/// [phone] is only non-null once the two are connected.
class MemberProfile {
  const MemberProfile({
    required this.id,
    required this.connection,
    this.displayName,
    this.avatarUrl,
    this.bio,
    this.country,
    this.phone,
    this.requestId,
  });

  final String id;
  final String? displayName;
  final String? avatarUrl;
  final String? bio;
  final String? country;
  final String? phone;

  /// none | pending_outgoing | pending_incoming | connected
  final String connection;

  /// Present when [connection] == 'pending_incoming' — accept target.
  final String? requestId;

  bool get isConnected => connection == 'connected';
  bool get isPendingOutgoing => connection == 'pending_outgoing';
  bool get isPendingIncoming => connection == 'pending_incoming';

  String get label =>
      displayName ?? '${id.substring(0, id.length.clamp(0, 6))}…';

  factory MemberProfile.fromJson(Map<String, dynamic> json) => MemberProfile(
        id: json['id'] as String,
        displayName: json['display_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        bio: json['bio'] as String?,
        country: json['country'] as String?,
        phone: json['phone'] as String?,
        connection: json['connection'] as String? ?? 'none',
        requestId: json['request_id'] as String?,
      );
}

/// A pending incoming request — name + avatar only until accepted.
class IncomingRequest {
  const IncomingRequest({
    required this.requestId,
    required this.requesterId,
    this.displayName,
    this.avatarUrl,
  });

  final String requestId;
  final String requesterId;
  final String? displayName;
  final String? avatarUrl;

  String get label =>
      displayName ?? '${requesterId.substring(0, requesterId.length.clamp(0, 6))}…';

  factory IncomingRequest.fromJson(Map<String, dynamic> json) =>
      IncomingRequest(
        requestId: json['request_id'] as String,
        requesterId: json['requester_id'] as String,
        displayName: json['display_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
      );
}

class ContactsRepository {
  ContactsRepository(this._dio, this.tripId);

  final Dio _dio;
  final String tripId;

  String get _base => '/trips/$tripId/contacts';

  Future<MemberProfile> profile(String userId) async {
    final r = await _dio.get<Map<String, dynamic>>('$_base/members/$userId');
    return MemberProfile.fromJson(r.data!);
  }

  Future<MemberProfile> request(String targetId) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '$_base/requests',
      data: {'target_id': targetId},
    );
    return MemberProfile.fromJson(r.data!);
  }

  Future<MemberProfile> accept(String requestId) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '$_base/requests/$requestId/accept',
    );
    return MemberProfile.fromJson(r.data!);
  }

  Future<void> decline(String requestId) async {
    await _dio.post('$_base/requests/$requestId/decline');
  }

  Future<List<IncomingRequest>> incoming() async {
    final r = await _dio.get<List<dynamic>>('$_base/requests/incoming');
    return (r.data ?? const [])
        .map((e) => IncomingRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

final contactsRepositoryProvider =
    FutureProvider.family<ContactsRepository, String>((ref, tripId) async {
  final dio = await ref.watch(apiClientProvider.future);
  return ContactsRepository(dio, tripId);
});

/// Count of pending incoming connection requests for a trip (for a badge).
final incomingRequestsProvider =
    FutureProvider.family<List<IncomingRequest>, String>((ref, tripId) async {
  final repo = await ref.watch(contactsRepositoryProvider(tripId).future);
  return repo.incoming();
});

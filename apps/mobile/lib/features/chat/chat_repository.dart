import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../shared/models/message.dart';

class ChatRepository {
  ChatRepository(this.dio);

  final Dio dio;

  Future<List<MessageDto>> history(String tripId, {int limit = 100}) async {
    final response = await dio.get(
      '/trips/$tripId/messages',
      queryParameters: {'limit': limit},
    );
    return (response.data as List)
        .map((m) => MessageDto.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  /// Sends via REST. Live in-trip sends should prefer the WebSocket so the
  /// other members see them with no round-trip; this is the fallback.
  Future<MessageDto> send(String tripId, String body) async {
    final response = await dio.post(
      '/trips/$tripId/messages',
      data: {'body': body},
    );
    return MessageDto.fromJson(response.data as Map<String, dynamic>);
  }

  /// Share a location pin. Stored as attachment_kind=location,
  /// attachment_url="lat,lng".
  Future<MessageDto> sendLocation(
    String tripId,
    double lat,
    double lng, {
    String body = '',
  }) async {
    final response = await dio.post(
      '/trips/$tripId/messages',
      data: {
        'body': body,
        'attachment_kind': 'location',
        'attachment_url': '$lat,$lng',
      },
    );
    return MessageDto.fromJson(response.data as Map<String, dynamic>);
  }

  /// Marshall-only: broadcast a pinned announcement to the whole pack.
  /// Pass [lat]/[lng] to make it a "regroup here" rally with a map pin.
  Future<MessageDto> sendAnnouncement(
    String tripId,
    String body, {
    double? lat,
    double? lng,
  }) async {
    final response = await dio.post(
      '/trips/$tripId/messages/announcement',
      data: {
        'body': body,
        if (lat != null && lng != null) 'lat': lat,
        if (lat != null && lng != null) 'lng': lng,
      },
    );
    return MessageDto.fromJson(response.data as Map<String, dynamic>);
  }

  /// The most recent pinned announcement, or null if there is none.
  Future<MessageDto?> latestAnnouncement(String tripId) async {
    final response = await dio.get('/trips/$tripId/messages/announcement');
    final data = response.data;
    if (data == null || data is! Map<String, dynamic>) return null;
    return MessageDto.fromJson(data);
  }

  /// Upload a photo / video / file and post it as a message. The server
  /// detects the kind from the content type.
  Future<MessageDto> sendAttachment(
    String tripId,
    String filePath, {
    String body = '',
  }) async {
    final form = FormData.fromMap({
      'body': body,
      'file': await MultipartFile.fromFile(filePath),
    });
    final response = await dio.post(
      '/trips/$tripId/messages/attachment',
      data: form,
    );
    return MessageDto.fromJson(response.data as Map<String, dynamic>);
  }
}

final chatRepositoryProvider = FutureProvider<ChatRepository>((ref) async {
  final dio = await ref.watch(apiClientProvider.future);
  return ChatRepository(dio);
});

/// Latest pinned announcement for a trip (null when none). Refetched on
/// demand (invalidated after the marshall posts a new one); live delivery to
/// already-connected members comes via the WS message stream.
final latestAnnouncementProvider =
    FutureProvider.autoDispose.family<MessageDto?, String>((ref, tripId) async {
  ref.watch(sessionEpochProvider);
  final repo = await ref.watch(chatRepositoryProvider.future);
  return repo.latestAnnouncement(tripId);
});

// autoDispose so re-entering a trip's chat re-fetches history from the server
// instead of showing a frozen first-load snapshot (live/mesh messages live in
// the per-screen buffer, which is discarded on dispose).
final chatHistoryProvider =
    FutureProvider.autoDispose.family<List<MessageDto>, String>((
  ref,
  tripId,
) async {
  ref.watch(sessionEpochProvider);
  final repo = await ref.watch(chatRepositoryProvider.future);
  return repo.history(tripId);
});

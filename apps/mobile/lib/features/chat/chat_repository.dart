import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
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
}

final chatRepositoryProvider = FutureProvider<ChatRepository>((ref) async {
  final dio = await ref.watch(apiClientProvider.future);
  return ChatRepository(dio);
});

final chatHistoryProvider = FutureProvider.family<List<MessageDto>, String>((
  ref,
  tripId,
) async {
  final repo = await ref.watch(chatRepositoryProvider.future);
  return repo.history(tripId);
});

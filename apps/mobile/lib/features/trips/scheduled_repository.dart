import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

class ScheduledAnnouncementDto {
  const ScheduledAnnouncementDto({
    required this.id,
    required this.body,
    required this.sendAt,
    required this.sent,
  });

  final String id;
  final String body;
  final DateTime sendAt;
  final bool sent;

  factory ScheduledAnnouncementDto.fromJson(Map<String, dynamic> json) =>
      ScheduledAnnouncementDto(
        id: json['id'] as String,
        body: json['body'] as String,
        sendAt: DateTime.parse(json['send_at'] as String).toLocal(),
        sent: json['sent'] as bool? ?? false,
      );
}

class ScheduledRepository {
  ScheduledRepository(this.dio);
  final Dio dio;

  Future<List<ScheduledAnnouncementDto>> list(String tripId) async {
    final res = await dio.get('/trips/$tripId/scheduled-announcements');
    return (res.data as List)
        .map(
          (e) => ScheduledAnnouncementDto.fromJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> create({
    required String tripId,
    required String body,
    required DateTime sendAt,
  }) async {
    await dio.post(
      '/trips/$tripId/scheduled-announcements',
      data: {
        'body': body,
        'send_at': sendAt.toUtc().toIso8601String(),
      },
    );
  }

  Future<void> cancel({
    required String tripId,
    required String scheduledId,
  }) async {
    await dio.delete('/trips/$tripId/scheduled-announcements/$scheduledId');
  }
}

final scheduledRepositoryProvider =
    FutureProvider<ScheduledRepository>((ref) async {
  final dio = await ref.watch(apiClientProvider.future);
  return ScheduledRepository(dio);
});

final tripScheduledProvider =
    FutureProvider.family<List<ScheduledAnnouncementDto>, String>(
        (ref, tripId) async {
  final repo = await ref.watch(scheduledRepositoryProvider.future);
  return repo.list(tripId);
});

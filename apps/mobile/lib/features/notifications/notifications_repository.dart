import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

/// Phase 9 — per-user push notification preferences. The FCM token is already
/// registered by push_service.dart; this controls which categories actually
/// notify, plus quiet hours. Safety (SOS/crash) always pushes regardless.

class NotificationPrefsDto {
  const NotificationPrefsDto({
    required this.enabled,
    required this.announcements,
    required this.nudges,
    required this.detours,
    required this.hazards,
    required this.chat,
    required this.checklist,
    this.quietStart,
    this.quietEnd,
  });

  final bool enabled;
  final bool announcements;
  final bool nudges;
  final bool detours;
  final bool hazards;
  final bool chat;
  final bool checklist;
  final int? quietStart;
  final int? quietEnd;

  bool get hasQuietHours => quietStart != null && quietEnd != null;

  factory NotificationPrefsDto.fromJson(Map<String, dynamic> j) =>
      NotificationPrefsDto(
        enabled: j['enabled'] as bool? ?? true,
        announcements: j['announcements'] as bool? ?? true,
        nudges: j['nudges'] as bool? ?? true,
        detours: j['detours'] as bool? ?? true,
        hazards: j['hazards'] as bool? ?? true,
        chat: j['chat'] as bool? ?? true,
        checklist: j['checklist'] as bool? ?? true,
        quietStart: (j['quiet_start'] as num?)?.toInt(),
        quietEnd: (j['quiet_end'] as num?)?.toInt(),
      );

  static const fallback = NotificationPrefsDto(
    enabled: true,
    announcements: true,
    nudges: true,
    detours: true,
    hazards: true,
    chat: true,
    checklist: true,
  );
}

class NotificationsRepository {
  NotificationsRepository(this.dio);
  final Dio dio;

  Future<NotificationPrefsDto> get() async {
    final res = await dio.get('/me/notifications');
    return NotificationPrefsDto.fromJson(res.data as Map<String, dynamic>);
  }

  Future<NotificationPrefsDto> update(Map<String, dynamic> patch) async {
    final res = await dio.patch('/me/notifications', data: patch);
    return NotificationPrefsDto.fromJson(res.data as Map<String, dynamic>);
  }
}

final notificationsRepositoryProvider =
    FutureProvider<NotificationsRepository>((ref) async {
  final dio = await ref.watch(apiClientProvider.future);
  return NotificationsRepository(dio);
});

final notificationPrefsProvider =
    FutureProvider.autoDispose<NotificationPrefsDto>((ref) async {
  final repo = await ref.watch(notificationsRepositoryProvider.future);
  return repo.get();
});

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

/// Phase 7 — gamification: personal badges and the per-trip leaderboard.

class BadgeDto {
  const BadgeDto({
    required this.code,
    required this.label,
    required this.description,
    required this.emoji,
    required this.goal,
    required this.progress,
    required this.earned,
    this.earnedAt,
  });

  final String code;
  final String label;
  final String description;
  final String emoji;
  final double goal;
  final double progress;
  final bool earned;
  final DateTime? earnedAt;

  double get fraction =>
      goal <= 0 ? 0 : (progress / goal).clamp(0, 1).toDouble();

  factory BadgeDto.fromJson(Map<String, dynamic> j) => BadgeDto(
        code: j['code'] as String,
        label: j['label'] as String? ?? '',
        description: j['description'] as String? ?? '',
        emoji: j['emoji'] as String? ?? '🏅',
        goal: (j['goal'] as num?)?.toDouble() ?? 1,
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        earned: j['earned'] as bool? ?? false,
        earnedAt: j['earned_at'] == null
            ? null
            : DateTime.tryParse(j['earned_at'] as String),
      );
}

class LeaderRowDto {
  const LeaderRowDto({
    required this.userId,
    required this.distanceKm,
    required this.messages,
    required this.hazards,
    required this.points,
    this.name,
    this.avatarUrl,
  });

  final String userId;
  final double distanceKm;
  final int messages;
  final int hazards;
  final double points;
  final String? name;
  final String? avatarUrl;

  factory LeaderRowDto.fromJson(Map<String, dynamic> j) => LeaderRowDto(
        userId: j['user_id'] as String,
        distanceKm: (j['distance_km'] as num?)?.toDouble() ?? 0,
        messages: (j['messages'] as num?)?.toInt() ?? 0,
        hazards: (j['hazards'] as num?)?.toInt() ?? 0,
        points: (j['points'] as num?)?.toDouble() ?? 0,
        name: j['name'] as String?,
        avatarUrl: j['avatar_url'] as String?,
      );
}

class AchievementsRepository {
  AchievementsRepository(this.dio);
  final Dio dio;

  Future<List<BadgeDto>> myBadges() async {
    final res = await dio.get('/me/badges');
    return (res.data as List)
        .map((e) => BadgeDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<LeaderRowDto>> leaderboard(String tripId) async {
    final res = await dio.get('/trips/$tripId/leaderboard');
    return (res.data as List)
        .map((e) => LeaderRowDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

final achievementsRepositoryProvider =
    FutureProvider<AchievementsRepository>((ref) async {
  final dio = await ref.watch(apiClientProvider.future);
  return AchievementsRepository(dio);
});

final myBadgesProvider =
    FutureProvider.autoDispose<List<BadgeDto>>((ref) async {
  final repo = await ref.watch(achievementsRepositoryProvider.future);
  return repo.myBadges();
});

final tripLeaderboardProvider = FutureProvider.autoDispose
    .family<List<LeaderRowDto>, String>((ref, tripId) async {
  final repo = await ref.watch(achievementsRepositoryProvider.future);
  return repo.leaderboard(tripId);
});

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';

/// One member's ready state in a ready-check.
class ReadyMember {
  const ReadyMember({required this.userId, required this.isReady});

  final String userId;
  final bool isReady;

  factory ReadyMember.fromJson(Map<String, dynamic> json) => ReadyMember(
        userId: json['user_id'] as String,
        isReady: json['is_ready'] as bool? ?? false,
      );
}

/// Snapshot of the whole pack's ready-check.
class ReadyState {
  const ReadyState({required this.members, required this.allReady});

  final List<ReadyMember> members;
  final bool allReady;

  Set<String> get readyUserIds => {
        for (final m in members)
          if (m.isReady) m.userId,
      };

  factory ReadyState.fromJson(Map<String, dynamic> json) => ReadyState(
        members: ((json['members'] as List?) ?? const [])
            .map((m) => ReadyMember.fromJson(m as Map<String, dynamic>))
            .toList(),
        allReady: json['all_ready'] as bool? ?? false,
      );
}

class ReadyCheckRepository {
  ReadyCheckRepository(this.dio);

  final Dio dio;

  Future<ReadyState> state(String tripId) async {
    final res = await dio.get('/trips/$tripId/ready_check');
    return ReadyState.fromJson(res.data as Map<String, dynamic>);
  }

  Future<ReadyState> toggle(String tripId, bool on) async {
    final res = await dio.post(
      '/trips/$tripId/ready_check',
      data: {'on': on},
    );
    return ReadyState.fromJson(res.data as Map<String, dynamic>);
  }
}

final readyCheckRepositoryProvider =
    FutureProvider<ReadyCheckRepository>((ref) async {
  final dio = await ref.watch(apiClientProvider.future);
  return ReadyCheckRepository(dio);
});

/// Initial ready-check snapshot for a trip. The panel seeds the live
/// controller from this, then relies on 'ready' WS frames for updates.
final readyCheckProvider =
    FutureProvider.autoDispose.family<ReadyState, String>((ref, tripId) async {
  ref.watch(sessionEpochProvider);
  final repo = await ref.watch(readyCheckRepositoryProvider.future);
  return repo.state(tripId);
});

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

class SafetyRepository {
  SafetyRepository(this.dio);
  final Dio dio;

  /// Mark a safety alert resolved ("I'm safe" / "all clear"). The server fans
  /// out a 'safety_resolved' frame so every member's alert banner clears.
  Future<void> resolve(String tripId, String alertId) async {
    await dio.post('/trips/$tripId/safety/$alertId/resolve');
  }
}

final safetyRepositoryProvider = FutureProvider<SafetyRepository>((ref) async {
  final dio = await ref.watch(apiClientProvider.future);
  return SafetyRepository(dio);
});

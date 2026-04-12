import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../shared/models/eta.dart';

class EtasRepository {
  EtasRepository(this.dio);

  final Dio dio;

  Future<TripEtas> get(String tripId) async {
    final response = await dio.get('/trips/$tripId/etas');
    return TripEtas.fromJson(response.data as Map<String, dynamic>);
  }
}

final etasRepositoryProvider = FutureProvider<EtasRepository>((ref) async {
  final dio = await ref.watch(apiClientProvider.future);
  return EtasRepository(dio);
});

final tripEtasProvider = FutureProvider.family<TripEtas, String>((
  ref,
  tripId,
) async {
  try {
    final repo = await ref.watch(etasRepositoryProvider.future);
    return await repo.get(tripId);
  } catch (_) {
    // ETA needs MAPBOX_SERVER_TOKEN configured. Until then, an empty
    // panel is friendlier than a red error.
    return TripEtas.empty;
  }
});

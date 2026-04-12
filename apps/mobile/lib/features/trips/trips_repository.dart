import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../shared/models/trip.dart';

class TripsRepository {
  TripsRepository(this.dio);

  final Dio dio;

  Future<List<TripDto>> listMyTrips() async {
    final response = await dio.get('/trips');
    final data = response.data as List;
    return data
        .map((t) => TripDto.fromJson(t as Map<String, dynamic>))
        .toList();
  }

  Future<TripDto> create({required String name}) async {
    final response = await dio.post('/trips', data: {'name': name});
    return TripDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<TripDto> joinByCode(String joinCode) async {
    final response = await dio.post(
      '/trips/join',
      data: {'join_code': joinCode},
    );
    return TripDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<TripDto> get(String tripId) async {
    final response = await dio.get('/trips/$tripId');
    return TripDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> setGhostMode({required String tripId, required bool on}) async {
    await dio.post('/trips/$tripId/ghost', queryParameters: {'on': on});
  }

  Future<void> end(String tripId) async {
    await dio.post('/trips/$tripId/end');
  }
}

final tripsRepositoryProvider = FutureProvider<TripsRepository>((ref) async {
  final dio = await ref.watch(apiClientProvider.future);
  return TripsRepository(dio);
});

/// List of the current user's trips. Watch this to refresh the trip list
/// screen — invalidate it after create/join/leave.
final myTripsProvider = FutureProvider<List<TripDto>>((ref) async {
  final repo = await ref.watch(tripsRepositoryProvider.future);
  return repo.listMyTrips();
});

final tripDetailProvider = FutureProvider.family<TripDto, String>((
  ref,
  tripId,
) async {
  final repo = await ref.watch(tripsRepositoryProvider.future);
  return repo.get(tripId);
});

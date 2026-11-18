import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
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

  Future<void> leave(String tripId) async {
    await dio.post('/trips/$tripId/leave');
  }

  /// Marshall assigns a pack role (driver, navigator, dj, …) to a member.
  Future<void> assignRole({
    required String tripId,
    required String userId,
    required String role,
  }) async {
    await dio
        .patch('/trips/$tripId/members/$userId/role', data: {'role': role});
  }

  /// Marshall locks/unlocks the route so members can't edit stops.
  Future<void> setRouteLock({
    required String tripId,
    required bool locked,
  }) async {
    await dio.patch('/trips/$tripId/route-lock', data: {'locked': locked});
  }

  /// Marshall sets the cruising pace target (km/h) and max straggler gap (km).
  Future<void> updateSettings({
    required String tripId,
    int? targetPaceKmh,
    double? maxGapKm,
  }) async {
    final data = <String, dynamic>{};
    if (targetPaceKmh != null) data['target_pace_kmh'] = targetPaceKmh;
    if (maxGapKm != null) data['max_gap_km'] = maxGapKm;
    await dio.patch('/trips/$tripId/settings', data: data);
  }

  /// Marshall mutes/unmutes a member.
  Future<void> muteMember({
    required String tripId,
    required String userId,
    required bool muted,
  }) async {
    await dio
        .patch('/trips/$tripId/members/$userId/mute', data: {'muted': muted});
  }

  /// Assign a member to a vehicle (members can set their own).
  Future<void> setVehicle({
    required String tripId,
    required String userId,
    required String? vehicleLabel,
  }) async {
    await dio.patch('/trips/$tripId/members/$userId/vehicle',
        data: {'vehicle_label': vehicleLabel});
  }

  /// Marshall removes a member from the pack.
  Future<void> removeMember({
    required String tripId,
    required String userId,
  }) async {
    await dio.post('/trips/$tripId/members/$userId/remove');
  }

  /// Hand the marshall role to another member (old owner becomes co-marshall).
  Future<void> transferMarshall({
    required String tripId,
    required String newOwnerId,
  }) async {
    await dio
        .post('/trips/$tripId/transfer', data: {'new_owner_id': newOwnerId});
  }
}

final tripsRepositoryProvider = FutureProvider<TripsRepository>((ref) async {
  final dio = await ref.watch(apiClientProvider.future);
  return TripsRepository(dio);
});

/// List of the current user's trips. Watch this to refresh the trip list
/// screen — invalidate it after create/join/leave.
final myTripsProvider = FutureProvider<List<TripDto>>((ref) async {
  ref.watch(sessionEpochProvider);
  final repo = await ref.watch(tripsRepositoryProvider.future);
  return repo.listMyTrips();
});

final tripDetailProvider = FutureProvider.family<TripDto, String>((
  ref,
  tripId,
) async {
  ref.watch(sessionEpochProvider);
  final repo = await ref.watch(tripsRepositoryProvider.future);
  return repo.get(tripId);
});

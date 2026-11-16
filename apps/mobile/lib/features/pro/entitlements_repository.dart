import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api_client.dart';

/// Phase 10 — Pro entitlements and route/calendar exports.

class EntitlementsDto {
  const EntitlementsDto({
    required this.plan,
    required this.maxTripMembers,
    required this.offlineTiles,
    required this.routeExports,
    required this.advancedWeather,
    required this.prioritySupport,
  });

  final String plan;
  final int maxTripMembers;
  final bool offlineTiles;
  final bool routeExports;
  final bool advancedWeather;
  final bool prioritySupport;

  bool get isPro => plan != 'free';

  factory EntitlementsDto.fromJson(Map<String, dynamic> j) => EntitlementsDto(
        plan: j['plan'] as String? ?? 'free',
        maxTripMembers: (j['max_trip_members'] as num?)?.toInt() ?? 5,
        offlineTiles: j['offline_tiles'] as bool? ?? false,
        routeExports: j['route_exports'] as bool? ?? false,
        advancedWeather: j['advanced_weather'] as bool? ?? false,
        prioritySupport: j['priority_support'] as bool? ?? false,
      );

  static const free = EntitlementsDto(
    plan: 'free',
    maxTripMembers: 5,
    offlineTiles: false,
    routeExports: false,
    advancedWeather: false,
    prioritySupport: false,
  );
}

class ProRepository {
  ProRepository(this.dio);
  final Dio dio;

  Future<EntitlementsDto> entitlements() async {
    final res = await dio.get('/me/entitlements');
    return EntitlementsDto.fromJson(res.data as Map<String, dynamic>);
  }

  /// Download a trip export ('gpx' or 'ics') to a local file and return its
  /// path. Uses the authorized Dio client so the Bearer token is attached.
  Future<String> downloadExport(String tripId, String kind) async {
    final path =
        kind == 'ics' ? '/trips/$tripId/trip.ics' : '/trips/$tripId/export.gpx';
    final res = await dio.get<String>(
      path,
      options: Options(responseType: ResponseType.plain),
    );
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/packpath-$tripId.$kind');
    await file.writeAsString(res.data ?? '');
    return file.path;
  }

  /// Record upgrade intent (actual payment handled by the provider webhook;
  /// the plan stays pending until then).
  Future<void> recordUpgradeIntent(String plan, String source) async {
    await dio.post('/me/subscriptions', data: {
      'provider': 'razorpay',
      'plan': plan,
      'paywall_source': source,
      'currency': 'INR',
    });
  }
}

final proRepositoryProvider = FutureProvider<ProRepository>((ref) async {
  final dio = await ref.watch(apiClientProvider.future);
  return ProRepository(dio);
});

final entitlementsProvider =
    FutureProvider.autoDispose<EntitlementsDto>((ref) async {
  final repo = await ref.watch(proRepositoryProvider.future);
  return repo.entitlements();
});

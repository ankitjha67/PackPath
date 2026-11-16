import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

/// Phase 8 — personalization. Server-synced user preferences (units, temp
/// scale, default map style, vehicle profile) plus the formatting helpers that
/// apply them across the UI.

const kVehicleTypes = <String>[
  'motorcycle',
  'scooter',
  'hatchback',
  'sedan',
  'suv',
  'van',
  'truck',
  'bicycle',
  'other',
];

class PreferencesDto {
  const PreferencesDto({
    required this.units,
    required this.tempUnit,
    required this.mapStyle,
    required this.vehicleType,
    required this.shareLocationDefault,
    this.mileageKmpl,
  });

  /// 'metric' or 'imperial'.
  final String units;

  /// 'c' or 'f'.
  final String tempUnit;
  final String mapStyle;
  final String vehicleType;
  final bool shareLocationDefault;
  final double? mileageKmpl;

  bool get imperial => units == 'imperial';
  bool get fahrenheit => tempUnit == 'f';

  /// Format a distance given in km in the user's chosen units.
  String formatDistance(double km) {
    if (imperial) {
      final mi = km * 0.621371;
      return '${mi.toStringAsFixed(mi >= 10 ? 0 : 1)} mi';
    }
    return '${km.toStringAsFixed(km >= 10 ? 0 : 1)} km';
  }

  /// Format a temperature given in °C in the user's chosen scale.
  String formatTemp(double celsius) {
    if (fahrenheit) {
      return '${(celsius * 9 / 5 + 32).round()}°F';
    }
    return '${celsius.round()}°C';
  }

  PreferencesDto copyWith({
    String? units,
    String? tempUnit,
    String? mapStyle,
    String? vehicleType,
    bool? shareLocationDefault,
    double? mileageKmpl,
  }) =>
      PreferencesDto(
        units: units ?? this.units,
        tempUnit: tempUnit ?? this.tempUnit,
        mapStyle: mapStyle ?? this.mapStyle,
        vehicleType: vehicleType ?? this.vehicleType,
        shareLocationDefault: shareLocationDefault ?? this.shareLocationDefault,
        mileageKmpl: mileageKmpl ?? this.mileageKmpl,
      );

  factory PreferencesDto.fromJson(Map<String, dynamic> j) => PreferencesDto(
        units: j['units'] as String? ?? 'metric',
        tempUnit: j['temp_unit'] as String? ?? 'c',
        mapStyle: j['map_style'] as String? ?? 'mapbox',
        vehicleType: j['vehicle_type'] as String? ?? 'hatchback',
        shareLocationDefault: j['share_location_default'] as bool? ?? true,
        mileageKmpl: (j['mileage_kmpl'] as num?)?.toDouble(),
      );

  /// A safe default used before the server value loads.
  static const fallback = PreferencesDto(
    units: 'metric',
    tempUnit: 'c',
    mapStyle: 'mapbox',
    vehicleType: 'hatchback',
    shareLocationDefault: true,
  );
}

class PreferencesRepository {
  PreferencesRepository(this.dio);
  final Dio dio;

  Future<PreferencesDto> get() async {
    final res = await dio.get('/me/preferences');
    return PreferencesDto.fromJson(res.data as Map<String, dynamic>);
  }

  Future<PreferencesDto> update(Map<String, dynamic> patch) async {
    final res = await dio.patch('/me/preferences', data: patch);
    return PreferencesDto.fromJson(res.data as Map<String, dynamic>);
  }
}

final preferencesRepositoryProvider =
    FutureProvider<PreferencesRepository>((ref) async {
  final dio = await ref.watch(apiClientProvider.future);
  return PreferencesRepository(dio);
});

/// The current user's preferences. Falls back to metric defaults until loaded
/// or if the fetch fails, so callers can read synchronously via `valueOrNull`.
final preferencesProvider =
    FutureProvider.autoDispose<PreferencesDto>((ref) async {
  final repo = await ref.watch(preferencesRepositoryProvider.future);
  return repo.get();
});

/// Convenience: the effective preferences right now (fallback until loaded).
PreferencesDto effectivePreferences(WidgetRef ref) =>
    ref.watch(preferencesProvider).valueOrNull ?? PreferencesDto.fallback;

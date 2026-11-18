import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_client.dart';

/// Phase 5 — member-reported road hazards and group detour votes.
///
/// Both live under /trips/{tripId}/navigation and fan out over the trip
/// WebSocket (handled in LiveTripController); these REST calls are the write
/// path plus the open-screen snapshot.

/// The kinds of hazard a member can drop, with a label + glyph for the UI.
class HazardKind {
  const HazardKind(this.id, this.label, this.emoji);
  final String id;
  final String label;
  final String emoji;
}

const kHazardKinds = <HazardKind>[
  HazardKind('pothole', 'Pothole', '🕳️'),
  HazardKind('accident', 'Accident', '💥'),
  HazardKind('police', 'Police', '🚓'),
  HazardKind('traffic', 'Traffic jam', '🚗'),
  HazardKind('roadblock', 'Road block', '🚧'),
  HazardKind('animal', 'Animal', '🐄'),
  HazardKind('debris', 'Debris', '🪨'),
  HazardKind('flood', 'Flooding', '🌊'),
  HazardKind('construction', 'Construction', '👷'),
  HazardKind('fuel_closed', 'Fuel closed', '⛽'),
  HazardKind('landslide', 'Landslide', '⛰️'),
  HazardKind('other', 'Other', '⚠️'),
];

HazardKind hazardKindFor(String id) => kHazardKinds.firstWhere(
      (k) => k.id == id,
      orElse: () => const HazardKind('other', 'Hazard', '⚠️'),
    );

class RoadHazardDto {
  const RoadHazardDto({
    required this.id,
    required this.kind,
    required this.severity,
    required this.lat,
    required this.lng,
    this.note,
    this.reporterName,
    this.reporterId,
  });

  final String id;
  final String kind;
  final String severity;
  final double lat;
  final double lng;
  final String? note;
  final String? reporterName;
  final String? reporterId;

  LatLng get latLng => LatLng(lat, lng);

  factory RoadHazardDto.fromJson(Map<String, dynamic> j) => RoadHazardDto(
        id: j['id'] as String,
        kind: j['kind'] as String? ?? 'other',
        severity: j['severity'] as String? ?? 'warn',
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        note: j['note'] as String?,
        reporterName: j['reporter_name'] as String?,
        reporterId: j['user_id'] as String? ?? j['reporter_id'] as String?,
      );
}

class DetourDto {
  const DetourDto({
    required this.id,
    required this.label,
    required this.lat,
    required this.lng,
    required this.yes,
    required this.no,
    this.reason,
    this.proposerName,
    this.proposerId,
    this.establishmentId,
    this.myVote,
    this.outcome,
  });

  final String id;
  final String label;
  final double lat;
  final double lng;
  final int yes;
  final int no;
  final String? reason;
  final String? proposerName;
  final String? proposerId;
  final String? establishmentId;
  final String? myVote;
  final String? outcome;

  LatLng get latLng => LatLng(lat, lng);

  factory DetourDto.fromJson(Map<String, dynamic> j) => DetourDto(
        id: j['id'] as String,
        label: j['label'] as String? ?? 'Detour',
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        yes: (j['yes'] as num?)?.toInt() ?? 0,
        no: (j['no'] as num?)?.toInt() ?? 0,
        reason: j['reason'] as String?,
        proposerName: j['proposer_name'] as String?,
        proposerId: j['proposed_by'] as String? ?? j['proposer_id'] as String?,
        establishmentId: j['establishment_id'] as String?,
        myVote: j['my_vote'] as String?,
        outcome: j['outcome'] as String?,
      );
}

class NavigationRepository {
  NavigationRepository(this.dio, this.tripId);

  final Dio dio;
  final String tripId;

  String get _base => '/trips/$tripId/navigation';

  // --- road hazards ---
  Future<RoadHazardDto> reportHazard({
    required String kind,
    required String severity,
    required double lat,
    required double lng,
    String? note,
  }) async {
    final res = await dio.post(
      '$_base/hazards',
      data: {
        'kind': kind,
        'severity': severity,
        'lat': lat,
        'lng': lng,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
    return RoadHazardDto.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<RoadHazardDto>> hazards() async {
    final res = await dio.get('$_base/hazards');
    return (res.data as List)
        .map((e) => RoadHazardDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> clearHazard(String id) async {
    await dio.post('$_base/hazards/$id/clear');
  }

  // --- detours ---
  Future<DetourDto> proposeDetour({
    required String label,
    required double lat,
    required double lng,
    String? reason,
    String? establishmentId,
  }) async {
    final res = await dio.post(
      '$_base/detours',
      data: {
        'label': label,
        'lat': lat,
        'lng': lng,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
        if (establishmentId != null) 'establishment_id': establishmentId,
      },
    );
    return DetourDto.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<DetourDto>> detours() async {
    final res = await dio.get('$_base/detours');
    return (res.data as List)
        .map((e) => DetourDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<DetourDto> vote(String id, String choice) async {
    final res = await dio.post(
      '$_base/detours/$id/vote',
      data: {
        'choice': choice,
      },
    );
    return DetourDto.fromJson(res.data as Map<String, dynamic>);
  }

  Future<DetourDto> close(String id, String outcome) async {
    final res = await dio.post(
      '$_base/detours/$id/close',
      queryParameters: {'outcome': outcome},
    );
    return DetourDto.fromJson(res.data as Map<String, dynamic>);
  }
}

final navigationRepositoryProvider =
    FutureProvider.autoDispose.family<NavigationRepository, String>((
  ref,
  tripId,
) async {
  final dio = await ref.watch(apiClientProvider.future);
  return NavigationRepository(dio, tripId);
});

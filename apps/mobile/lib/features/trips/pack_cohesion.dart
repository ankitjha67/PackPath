import 'package:latlong2/latlong.dart';

import '../../shared/models/member_location.dart';

/// How far a member (in metres) is from the pack's centre.
class MemberDistance {
  const MemberDistance({required this.userId, required this.metresFromPack});

  final String userId;
  final double metresFromPack;
}

/// A snapshot of how tightly the pack is travelling together, derived purely
/// from live member positions (no backend). The marshall uses it to spot who
/// is trailing.
class PackCohesion {
  const PackCohesion({
    required this.centre,
    required this.stragglers,
    required this.spreadMetres,
    required this.memberCount,
  });

  /// Geographic centre of the pack (null when no members are live).
  final LatLng? centre;

  /// Members beyond the straggler threshold, farthest first.
  final List<MemberDistance> stragglers;

  /// Distance from the centre to the farthest member, in metres.
  final double spreadMetres;

  /// Number of members with a live position.
  final int memberCount;

  bool get isTogether => stragglers.isEmpty;

  Set<String> get stragglerIds => {for (final s in stragglers) s.userId};

  static const empty = PackCohesion(
    centre: null,
    stragglers: [],
    spreadMetres: 0,
    memberCount: 0,
  );
}

const _distance = Distance();

/// Absolute floor for the straggler threshold so a tightly-parked pack never
/// flags noise as "trailing".
const double _minStragglerMetres = 150;

/// Compute pack cohesion from the current live member positions.
///
/// A member counts as a straggler when they are farther from the pack centre
/// than `max(150 m, 2.2 × median distance)` — the adaptive term keeps the
/// call sensible whether the pack is strolling a plaza or strung along a
/// highway.
PackCohesion computeCohesion(Map<String, MemberLocation> members) {
  if (members.isEmpty) return PackCohesion.empty;
  final locs = members.values.toList();

  var lat = 0.0;
  var lng = 0.0;
  for (final m in locs) {
    lat += m.position.latitude;
    lng += m.position.longitude;
  }
  final centre = LatLng(lat / locs.length, lng / locs.length);

  final dists = <MemberDistance>[];
  var spread = 0.0;
  for (final m in locs) {
    final d = _distance.as(LengthUnit.Meter, centre, m.position);
    dists.add(MemberDistance(userId: m.userId, metresFromPack: d));
    if (d > spread) spread = d;
  }

  // Median distance from the centre.
  final sorted = [for (final d in dists) d.metresFromPack]..sort();
  final mid = sorted.length ~/ 2;
  final median =
      sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;

  final threshold =
      median * 2.2 > _minStragglerMetres ? median * 2.2 : _minStragglerMetres;

  final stragglers = dists.where((d) => d.metresFromPack > threshold).toList()
    ..sort((a, b) => b.metresFromPack.compareTo(a.metresFromPack));

  return PackCohesion(
    centre: centre,
    stragglers: stragglers,
    spreadMetres: spread,
    memberCount: locs.length,
  );
}

/// Human label for a distance, e.g. "420 m" or "2.3 km".
String formatMetres(double m) =>
    m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';

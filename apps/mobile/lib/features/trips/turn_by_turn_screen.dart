import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../map/live_trip_controller.dart';
import '../map/map_providers.dart';
import '../preferences/preferences_repository.dart';
import '../profile/me_repository.dart';
import 'waypoints_repository.dart';

/// Turn-by-turn navigation. Maneuvers are derived client-side from the route
/// polyline (bearing changes at vertices), so it gives Google-Maps-style
/// "In 300 m, turn left" guidance with live distance/ETA from the GPS stream.
class TurnByTurnScreen extends ConsumerStatefulWidget {
  const TurnByTurnScreen({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<TurnByTurnScreen> createState() => _TurnByTurnScreenState();
}

class _Maneuver {
  _Maneuver(this.at, this.turnDeg);
  final LatLng at;
  final double turnDeg; // + right, - left

  IconData get icon {
    if (turnDeg.abs() < 25) return Icons.straight;
    if (turnDeg >= 70) return Icons.turn_right;
    if (turnDeg >= 25) return Icons.turn_slight_right;
    if (turnDeg <= -70) return Icons.turn_left;
    return Icons.turn_slight_left;
  }

  String get text {
    if (turnDeg.abs() < 25) return 'Continue straight';
    final side = turnDeg > 0 ? 'right' : 'left';
    final sharp = turnDeg.abs() >= 70 ? 'Turn' : 'Bear';
    return '$sharp $side';
  }
}

class _TurnByTurnScreenState extends ConsumerState<TurnByTurnScreen> {
  final MapController _map = MapController();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recenter());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _map.dispose();
    super.dispose();
  }

  LatLng? _myPos() {
    final myId = ref.read(meProvider).valueOrNull?.id;
    if (myId == null) return null;
    return ref.read(liveTripProvider(widget.tripId)).members[myId]?.position;
  }

  void _recenter() {
    final p = _myPos();
    if (p != null) {
      try {
        _map.move(p, _map.camera.zoom);
      } catch (_) {}
    }
  }

  List<_Maneuver> _maneuvers(List<LatLng> pts) {
    const dist = Distance();
    final out = <_Maneuver>[];
    for (var i = 1; i < pts.length - 1; i++) {
      final b1 = dist.bearing(pts[i - 1], pts[i]);
      final b2 = dist.bearing(pts[i], pts[i + 1]);
      var turn = (b2 - b1 + 540) % 360 - 180; // [-180,180]
      if (turn.abs() >= 20) out.add(_Maneuver(pts[i], turn.toDouble()));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mapProvider = ref.watch(mapProviderControllerProvider);
    final routeAsync = ref.watch(tripRouteProvider(widget.tripId));
    final myId = ref.watch(meProvider).valueOrNull?.id;
    final live = ref.watch(liveTripProvider(widget.tripId));
    final prefs = effectivePreferences(ref);
    final me = myId == null ? null : live.members[myId];
    final myPos = me?.position;
    final speedKmh = (me?.speed ?? 0) * 3.6;

    final route = routeAsync.valueOrNull;
    final pts = route?.points ?? const <LatLng>[];
    final maneuvers = pts.length >= 3 ? _maneuvers(pts) : <_Maneuver>[];

    // Next maneuver ahead of me + distance to it.
    const dist = Distance();
    _Maneuver? next;
    double nextM = double.infinity;
    if (myPos != null) {
      for (final mv in maneuvers) {
        final d = dist.as(LengthUnit.Meter, myPos, mv.at);
        if (d < nextM && d > 15) {
          nextM = d;
          next = mv;
        }
      }
    }
    // Remaining distance to the final point + ETA.
    final destM = (myPos != null && pts.isNotEmpty)
        ? dist.as(LengthUnit.Meter, myPos, pts.last)
        : (route?.distanceM ?? 0);
    final paceKmh = speedKmh > 2 ? speedKmh : 20.0;
    final etaMin = destM > 0 ? (destM / 1000) / paceKmh * 60 : 0;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: myPos ??
                  (pts.isNotEmpty ? pts.first : const LatLng(28.6, 77.2)),
              initialZoom: 16,
            ),
            children: [
              // Street-level raster tiles. (The India-correct Ola vector
              // basemap is used on the main map; at turn-by-turn zoom national
              // borders aren't visible, and a second vector layer sharing the
              // main map's cached providers renders blank.)
              TileLayer(
                urlTemplate: mapProvider.tileUrlTemplate,
                userAgentPackageName: 'app.packpath.mobile',
                maxZoom: 19,
              ),
              if (pts.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                        points: pts, strokeWidth: 7, color: scheme.primary),
                  ],
                ),
              if (myPos != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: myPos,
                      width: 30,
                      height: 30,
                      child: Transform.rotate(
                        angle: ((me?.heading ?? 0) * math.pi / 180),
                        child: Icon(
                          Icons.navigation,
                          color: scheme.primary,
                          size: 30,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          // Maneuver banner.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(AppSpacing.base),
                padding: const EdgeInsets.all(AppSpacing.base),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: AppRadii.full,
                ),
                child: Row(
                  children: [
                    Icon(
                      next?.icon ?? Icons.flag,
                      color: scheme.onPrimary,
                      size: 44,
                    ),
                    const SizedBox(width: AppSpacing.base),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            myPos == null
                                ? 'Waiting for GPS…'
                                : next == null
                                    ? 'Head to destination'
                                    : 'In ${_m(nextM, prefs)}',
                            style: textTheme.titleMedium?.copyWith(
                              color: scheme.onPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            next?.text ?? 'Follow the route',
                            style: textTheme.bodyMedium?.copyWith(
                              color: scheme.onPrimary.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Bottom ETA bar.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(AppSpacing.base),
                padding: const EdgeInsets.all(AppSpacing.base),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: AppRadii.full,
                ),
                child: Row(
                  children: [
                    _stat(context, '${etaMin.round()}', 'min'),
                    const SizedBox(width: AppSpacing.lg),
                    _stat(
                      context,
                      _m(destM, prefs).split(' ').first,
                      _m(destM, prefs).split(' ').last,
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    _stat(context, '${speedKmh.round()}', 'km/h'),
                    const Spacer(),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.error,
                        shape: const RoundedRectangleBorder(
                            borderRadius: AppRadii.full),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('End'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String v, String k) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(v, style: textTheme.titleLarge?.copyWith(height: 1)),
        Text(
          k,
          style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  String _m(double m, PreferencesDto prefs) {
    if (prefs.imperial) {
      final mi = m / 1609.34;
      return mi >= 0.1
          ? '${mi.toStringAsFixed(1)} mi'
          : '${(m * 3.281).round()} ft';
    }
    return m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';
  }
}

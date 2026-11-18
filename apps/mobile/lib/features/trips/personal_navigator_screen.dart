import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/models/member_location.dart';
import '../../shared/models/waypoint.dart';
import '../map/live_trip_controller.dart';
import '../preferences/preferences_repository.dart';
import '../profile/me_repository.dart';
import 'waypoints_repository.dart';

/// Personal Navigator — the `designs/personal_navigator_card` flow: a focused
/// turn-card to the next waypoint with a live compass arrow, distance, bearing
/// and an ETA from current pace. Pure client-side from live telemetry.
class PersonalNavigatorScreen extends ConsumerStatefulWidget {
  const PersonalNavigatorScreen({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<PersonalNavigatorScreen> createState() =>
      _PersonalNavigatorScreenState();
}

class _PersonalNavigatorScreenState
    extends ConsumerState<PersonalNavigatorScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final myId = ref.watch(meProvider).valueOrNull?.id;
    final live = ref.watch(liveTripProvider(widget.tripId));
    final prefs = effectivePreferences(ref);
    final waypoints =
        ref.watch(tripWaypointsProvider(widget.tripId)).valueOrNull ??
            const <WaypointDto>[];
    final me = myId == null ? null : live.members[myId];

    return Scaffold(
      appBar: AppBar(title: const Text('Navigator')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: _build(context, scheme, textTheme, me, waypoints, prefs),
      ),
    );
  }

  Widget _build(
    BuildContext context,
    ColorScheme scheme,
    TextTheme textTheme,
    MemberLocation? me,
    List<WaypointDto> waypoints,
    PreferencesDto prefs,
  ) {
    if (me == null) {
      return _centered(
        textTheme,
        'Waiting for your GPS fix…\nMove outdoors and keep PackPath open.',
      );
    }
    if (waypoints.isEmpty) {
      return _centered(
        textTheme,
        'No waypoints on this trip yet.\nLong-press the map to add one.',
      );
    }
    // Nearest waypoint ahead.
    const dist = Distance();
    WaypointDto target = waypoints.first;
    double best = double.infinity;
    for (final w in waypoints) {
      final d = dist.as(LengthUnit.Meter, me.position, w.latLng);
      if (d < best) {
        best = d;
        target = w;
      }
    }
    final bearing = dist.bearing(me.position, target.latLng);
    final heading = (me.speed ?? 0) > 0.5 ? (me.heading ?? 0.0) : 0.0;
    final relative = ((bearing - heading) % 360) * math.pi / 180;
    final paceKmh = (me.speed ?? 0) * 3.6;
    final etaMin = paceKmh > 1 ? (best / 1000) / paceKmh * 60 : null;

    return Column(
      children: [
        const SizedBox(height: AppSpacing.sm),
        Text(
          'NEXT WAYPOINT',
          style: textTheme.labelMedium
              ?.copyWith(letterSpacing: 2, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(
          target.name,
          style: textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xl),
        // Compass dial with the heading arrow.
        SizedBox(
          width: 240,
          height: 240,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.surfaceContainerLow,
                ),
              ),
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: scheme.surfaceContainerHigh, width: 2),
                ),
              ),
              Transform.rotate(
                angle: relative,
                child: Icon(Icons.navigation, size: 110, color: scheme.primary),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Expanded(
              child:
                  _stat(context, 'DISTANCE', prefs.formatDistance(best / 1000)),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _stat(
                context,
                'BEARING',
                '${bearing.round()}° ${_compass(bearing)}',
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _stat(
                context,
                'ETA',
                etaMin == null ? '—' : '${etaMin.round()} min',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _centered(TextTheme t, String msg) => Center(
        child: Text(msg, textAlign: TextAlign.center, style: t.bodyLarge),
      );

  Widget _stat(BuildContext context, String k, String v) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadii.full,
      ),
      child: Column(
        children: [
          Text(
            k,
            style: textTheme.labelSmall
                ?.copyWith(letterSpacing: 1, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(v, style: textTheme.titleMedium, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  static String _compass(double deg) {
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return dirs[(((deg % 360) + 22.5) ~/ 45) % 8];
  }
}

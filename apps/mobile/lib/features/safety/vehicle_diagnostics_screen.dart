import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/models/member_location.dart';
import '../map/live_trip_controller.dart';
import '../preferences/preferences_repository.dart';
import '../profile/me_repository.dart';

/// Vehicle Diagnostics — the `designs/vehicle_diagnostics` HUD, driven by the
/// device telemetry PackPath already streams: phone battery, live pace,
/// heading, GPS-fix freshness and uplink signal, plus the configured vehicle.
class VehicleDiagnosticsScreen extends ConsumerStatefulWidget {
  const VehicleDiagnosticsScreen({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<VehicleDiagnosticsScreen> createState() =>
      _VehicleDiagnosticsScreenState();
}

class _VehicleDiagnosticsScreenState
    extends ConsumerState<VehicleDiagnosticsScreen> {
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
    final MemberLocation? me = myId == null ? null : live.members[myId];

    final battery = me?.battery;
    final paceKmh = (me?.speed ?? 0) * 3.6;
    final heading = me?.heading;
    final ageSec =
        me == null ? null : DateTime.now().difference(me.lastUpdate).inSeconds;
    final gpsOk = me != null;
    final signalOk = ageSec != null && ageSec < 30;

    return Scaffold(
      appBar: AppBar(title: const Text('Vehicle diagnostics')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: AppRadii.full,
            ),
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                Icon(
                  _vehicleIcon(prefs.vehicleType),
                  size: 56,
                  color: scheme.primary,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(_label(prefs.vehicleType), style: textTheme.titleLarge),
                Text(
                  gpsOk ? 'SYSTEMS NOMINAL' : 'AWAITING GPS',
                  style: textTheme.labelMedium?.copyWith(
                    letterSpacing: 1.5,
                    color: gpsOk ? Colors.green : scheme.tertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
            childAspectRatio: 1.5,
            children: [
              _gauge(
                context,
                'BATTERY',
                battery == null ? '—' : '$battery%',
                value: battery == null ? null : battery / 100,
                warn: battery != null && battery <= 20,
              ),
              _gauge(
                context,
                'PACE',
                paceKmh > 0.5
                    ? (prefs.imperial
                        ? '${(paceKmh * 0.621371).round()} mph'
                        : '${paceKmh.round()} km/h')
                    : 'idle',
                value: (paceKmh / 120).clamp(0, 1).toDouble(),
              ),
              _gauge(
                context,
                'HEADING',
                heading == null
                    ? '—'
                    : '${heading.round()}° ${_compass(heading)}',
                value: heading == null ? null : (heading % 360) / 360,
              ),
              _gauge(
                context,
                'GPS FIX',
                gpsOk ? 'LOCKED' : 'SEARCHING',
                value: gpsOk ? 1 : 0,
                warn: !gpsOk,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: AppRadii.full,
            ),
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Row(
              children: [
                Icon(
                  signalOk ? Icons.sensors : Icons.sensors_off,
                  color: signalOk ? Colors.green : scheme.error,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'UPLINK SIGNAL',
                        style: textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.2,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        ageSec == null
                            ? 'No fix yet'
                            : signalOk
                                ? 'Live — updated ${ageSec}s ago'
                                : 'Stale — ${ageSec}s since last fix',
                        style: textTheme.titleSmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gauge(
    BuildContext context,
    String k,
    String v, {
    double? value,
    bool warn = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final color = warn ? scheme.error : scheme.primary;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadii.full,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            k,
            style: textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              color: scheme.onSurfaceVariant,
            ),
          ),
          Text(
            v,
            style: textTheme.titleLarge?.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          ClipRRect(
            borderRadius: AppRadii.lg,
            child: LinearProgressIndicator(
              value: value,
              minHeight: 5,
              backgroundColor: scheme.surfaceContainerHigh,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  static IconData _vehicleIcon(String v) {
    switch (v) {
      case 'motorcycle':
        return Icons.two_wheeler;
      case 'scooter':
        return Icons.moped;
      case 'bicycle':
        return Icons.pedal_bike;
      case 'truck':
        return Icons.local_shipping;
      case 'van':
        return Icons.airport_shuttle;
      case 'suv':
        return Icons.directions_car_filled;
      default:
        return Icons.directions_car;
    }
  }

  static String _label(String v) =>
      v.isEmpty ? v : v[0].toUpperCase() + v.substring(1);

  static String _compass(double deg) {
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return dirs[(((deg % 360) + 22.5) ~/ 45) % 8];
  }
}

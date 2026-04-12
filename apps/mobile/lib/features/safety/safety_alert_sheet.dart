import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../map/live_trip_controller.dart';

/// Full-screen alert that pops over the trip map whenever a safety
/// frame ('sos', 'crash', 'speed', 'stranded', 'fatigue') arrives.
/// The owning screen is responsible for showing this when
/// `LiveTripState.activeSafetyAlert` becomes non-null.
class SafetyAlertSheet extends ConsumerWidget {
  const SafetyAlertSheet({
    super.key,
    required this.tripId,
    required this.alert,
  });

  final String tripId;
  final Map<String, dynamic> alert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = (alert['kind'] as String?) ?? 'safety';
    final severity = (alert['severity'] as String?) ?? 'warning';
    final color = severity == 'critical' ? Colors.red : Colors.orange;
    return WillPopScope(
      onWillPop: () async {
        ref.read(liveTripProvider(tripId).notifier).clearSafetyAlert();
        return true;
      },
      child: Scaffold(
        backgroundColor: color.withOpacity(0.95),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                Icon(_iconFor(kind), color: Colors.white, size: 96),
                const SizedBox(height: 24),
                Text(
                  _titleFor(kind),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _bodyFor(kind, alert),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: color,
                  ),
                  onPressed: () {
                    ref
                        .read(liveTripProvider(tripId).notifier)
                        .clearSafetyAlert();
                    Navigator.of(context).pop();
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('Acknowledge'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String kind) {
    switch (kind) {
      case 'sos':
        return Icons.sos;
      case 'crash':
        return Icons.car_crash;
      case 'stranded':
        return Icons.battery_alert;
      case 'speed':
        return Icons.speed;
      case 'fatigue':
        return Icons.bedtime;
    }
    return Icons.warning;
  }

  String _titleFor(String kind) {
    switch (kind) {
      case 'sos':
        return 'SOS — pack member needs help';
      case 'crash':
        return 'Possible crash detected';
      case 'stranded':
        return 'Member may be stranded';
      case 'speed':
        return 'Driving over the limit';
      case 'fatigue':
        return 'Driver fatigue likely';
    }
    return 'Safety alert';
  }

  String _bodyFor(String kind, Map<String, dynamic> alert) {
    final details = (alert['details'] as Map?) ?? {};
    switch (kind) {
      case 'speed':
        return 'Last reading: ${details['speed_kmh'] ?? '?'} km/h '
            '(limit ${details['limit_kmh'] ?? '?'}).';
      case 'stranded':
        return 'Battery at ${details['battery_pct'] ?? '?'}% with no '
            'recent movement.';
      case 'sos':
        return 'A trip member just hit SOS. Their last known location '
            'is on the map.';
      case 'crash':
        return 'Sudden deceleration detected. Tap acknowledge if false alarm.';
    }
    return 'Tap acknowledge once you have checked in.';
  }
}

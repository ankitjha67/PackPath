import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../map/live_trip_controller.dart';
import '../profile/me_repository.dart';
import 'emergency_contacts_repository.dart';
import 'safety_repository.dart';

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
    final alertId = alert['alert_id'] as String?;

    // Auto-dismiss if someone resolves this alert ("all clear") while open.
    ref.listen(liveTripProvider(tripId), (prev, next) {
      final stillActive = next.activeSafetyAlert?['alert_id'] == alertId;
      if (!stillActive && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          ref.read(liveTripProvider(tripId).notifier).clearSafetyAlert();
        }
      },
      child: Scaffold(
        backgroundColor: color.withValues(alpha: 0.95),
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
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => _alertEmergencyContacts(context, ref),
                  icon: const Icon(Icons.contact_phone),
                  label: const Text('Text my emergency contacts'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: color,
                  ),
                  onPressed: alertId == null
                      ? null
                      : () => _resolve(context, ref, alertId),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text("I'm safe — all clear"),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  // Pop only; PopScope.onPopInvokedWithResult clears the alert.
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Dismiss (for me only)',
                      style: TextStyle(color: Colors.white70)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _resolve(
      BuildContext context, WidgetRef ref, String alertId) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final repo = await ref.read(safetyRepositoryProvider.future);
      await repo.resolve(tripId, alertId);
      // The PopScope callback below owns clearSafetyAlert(); popping fires it.
      if (navigator.canPop()) navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not resolve: $e')));
    }
  }

  Future<void> _alertEmergencyContacts(
      BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final contacts =
        await ref.read(emergencyContactsRepositoryProvider.future).then(
              (r) => r.list(),
              onError: (_) => <EmergencyContact>[],
            );
    if (contacts.isEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text('No emergency contacts yet — add them in Profile.'),
      ));
      return;
    }
    // Attach my live location if available.
    final myId = ref.read(meProvider).valueOrNull?.id;
    final pos = myId == null
        ? null
        : ref.read(liveTripProvider(tripId)).members[myId]?.position;
    final locationLine = pos == null
        ? ''
        : ' My location: https://maps.google.com/?q=${pos.latitude},${pos.longitude}';
    final body = Uri.encodeComponent(
        'I need help — this is an emergency alert from PackPath.$locationLine');
    final recipients = contacts.map((c) => c.phone).join(',');
    final uri = Uri.parse('sms:$recipients?body=$body');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the SMS app.')),
      );
    }
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

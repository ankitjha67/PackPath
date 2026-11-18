import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../map/live_trip_controller.dart';
import '../profile/me_repository.dart';
import 'emergency_contacts_repository.dart';
import 'emergency_contacts_screen.dart';
import 'safety_repository.dart';

/// SOS Emergency Dashboard — the `designs/sos_emergency_dashboard` flow: a
/// single command surface for raising, broadcasting and clearing an emergency.
/// Active-alert status, a big SOS trigger, "I'm safe" resolve, and one-tap
/// contact alerting with the user's live location.
class SosDashboardScreen extends ConsumerWidget {
  const SosDashboardScreen({super.key, required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final live = ref.watch(liveTripProvider(tripId));
    final alert = live.activeSafetyAlert;
    final contactsAsync = ref.watch(emergencyContactsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Emergency')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          // Status card.
          Container(
            decoration: BoxDecoration(
              color: alert != null
                  ? scheme.errorContainer
                  : scheme.surfaceContainerLow,
              borderRadius: AppRadii.full,
            ),
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Icon(
                  alert != null ? Icons.emergency : Icons.shield_outlined,
                  color: alert != null ? scheme.error : Colors.green,
                  size: 40,
                ),
                const SizedBox(width: AppSpacing.base),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alert != null ? 'ALERT ACTIVE' : 'ALL CLEAR',
                        style: textTheme.labelMedium?.copyWith(
                          letterSpacing: 1.5,
                          color: alert != null ? scheme.error : Colors.green,
                        ),
                      ),
                      Text(
                        alert != null
                            ? '${alert['kind'] ?? 'SOS'} reported — respond below.'
                            : 'No active emergencies in this pack.',
                        style: textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Big SOS trigger.
          GestureDetector(
            onTap: () => _trigger(context, ref),
            child: Container(
              height: 160,
              decoration: BoxDecoration(
                color: scheme.error,
                shape: BoxShape.rectangle,
                borderRadius: AppRadii.full,
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sos, color: Colors.white, size: 56),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'HOLD-FREE SOS',
                    style: textTheme.titleMedium
                        ?.copyWith(color: Colors.white, letterSpacing: 1.5),
                  ),
                  Text(
                    'Alert the whole pack now',
                    style: textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
          if (alert != null) ...[
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green,
                minimumSize: const Size.fromHeight(52),
                shape:
                    const RoundedRectangleBorder(borderRadius: AppRadii.full),
              ),
              onPressed: () => _resolve(context, ref, alert),
              icon: const Icon(Icons.check_circle),
              label: const Text("I'm safe — all clear"),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text(
            'EMERGENCY CONTACTS',
            style: textTheme.labelMedium?.copyWith(
              letterSpacing: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          contactsAsync.when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (e, _) => Text('Could not load contacts: $e'),
            data: (contacts) {
              if (contacts.isEmpty) {
                return _manageCard(
                  context,
                  'No contacts yet — add people to alert on SOS.',
                );
              }
              return Column(
                children: [
                  for (final c in contacts)
                    Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: AppRadii.full,
                      ),
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(c.name),
                        subtitle: Text(c.phone),
                        trailing: IconButton(
                          icon: Icon(Icons.sms, color: scheme.primary),
                          onPressed: () => _textContacts(context, ref, [c]),
                        ),
                      ),
                    ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () => _textContacts(context, ref, contacts),
                    icon: const Icon(Icons.outgoing_mail),
                    label: const Text('Text all with my location'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const EmergencyContactsScreen(),
                      ),
                    ),
                    child: const Text('Manage contacts'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _manageCard(BuildContext context, String msg) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadii.full,
      ),
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        children: [
          Text(msg, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const EmergencyContactsScreen(),
              ),
            ),
            child: const Text('Add contacts'),
          ),
        ],
      ),
    );
  }

  Future<void> _trigger(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send SOS?'),
        content: const Text(
          'This alerts every pack member with your live location.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send SOS'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final sent = await ref
        .read(liveTripProvider(tripId).notifier)
        .sendSafety(kind: 'sos');
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          sent
              ? 'SOS sent to the pack.'
              : 'Offline — SOS queued, will send on reconnect.',
        ),
      ),
    );
  }

  Future<void> _resolve(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> alert,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final id = alert['alert_id'] as String?;
    if (id == null) return;
    try {
      final repo = await ref.read(safetyRepositoryProvider.future);
      await repo.resolve(tripId, id);
      ref.read(liveTripProvider(tripId).notifier).clearSafetyAlert();
      messenger
          .showSnackBar(const SnackBar(content: Text('Marked all clear.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not resolve: $e')));
    }
  }

  Future<void> _textContacts(
    BuildContext context,
    WidgetRef ref,
    List<EmergencyContact> contacts,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final myId = ref.read(meProvider).valueOrNull?.id;
    final pos = myId == null
        ? null
        : ref.read(liveTripProvider(tripId)).members[myId]?.position;
    final locationLine = pos == null
        ? ''
        : ' My location: https://maps.google.com/?q=${pos.latitude},${pos.longitude}';
    final body = Uri.encodeComponent(
      'I need help — emergency alert from PackPath.$locationLine',
    );
    final recipients = contacts.map((c) => c.phone).join(',');
    final uri = Uri.parse('sms:$recipients?body=$body');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the SMS app.')),
      );
    }
  }
}

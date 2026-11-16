import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/kinetic_path_tokens.dart';
import '../chat/chat_repository.dart';
import '../map/live_trip_controller.dart';
import '../profile/me_repository.dart';
import 'ready_check_panel.dart';
import 'trips_repository.dart';

/// Marshall Command — the `designs/marshall_command` control surface for the
/// pack marshall (trip owner): pack-readiness at a glance plus one-tap
/// broadcast, regroup and ready-check. Reuses the existing announcement and
/// ready-check paths.
class MarshallCommandScreen extends ConsumerWidget {
  const MarshallCommandScreen({super.key, required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<KineticPathTokens>()!;
    final tripAsync = ref.watch(tripDetailProvider(tripId));
    final live = ref.watch(liveTripProvider(tripId));
    final myId = ref.watch(meProvider).valueOrNull?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Marshall command')),
      body: tripAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
        data: (trip) {
          final isMarshall = myId != null && trip.ownerId == myId;
          if (!isMarshall) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'Marshall tools are for the trip owner.\n'
                  'Ask your marshall to coordinate the pack.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyLarge,
                ),
              ),
            );
          }
          final ready = live.readyUserIds.length;
          final total = trip.members.length;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.base),
            children: [
              // Readiness hero.
              Container(
                decoration: BoxDecoration(
                  gradient: tokens.ctaGradient,
                  borderRadius: AppRadii.full,
                ),
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PACK READINESS',
                        style: textTheme.labelMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                            letterSpacing: 1.5)),
                    Text('$ready / $total ready',
                        style: textTheme.displaySmall
                            ?.copyWith(color: Colors.white)),
                    Text('${live.onlineUserIds.length} online now',
                        style: textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9))),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('COMMANDS',
                  style: textTheme.labelMedium?.copyWith(
                      letterSpacing: 1.5, color: scheme.onSurfaceVariant)),
              const SizedBox(height: AppSpacing.sm),
              _command(
                  context,
                  Icons.campaign,
                  'Broadcast announcement',
                  'Send a pinned message to the whole pack',
                  () => _broadcast(context, ref)),
              _command(
                  context,
                  Icons.group_work,
                  'Regroup here',
                  'Call the pack to your current location',
                  () => _regroup(context, ref)),
              _command(context, Icons.how_to_reg, 'Ready check',
                  'See who is ready to move', () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => ReadyCheckPanel(tripId: tripId),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _command(BuildContext context, IconData icon, String title,
      String subtitle, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadii.full,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base, vertical: AppSpacing.sm),
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: Icon(icon, color: scheme.onPrimaryContainer),
        ),
        title: Text(title, style: textTheme.titleMedium),
        subtitle: Text(subtitle,
            style:
                textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Future<void> _broadcast(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Broadcast to the pack'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 280,
          decoration: const InputDecoration(
            hintText: 'e.g. Fuel stop in 10 minutes',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Broadcast'),
          ),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    await _send(context, ref, text);
  }

  Future<void> _regroup(BuildContext context, WidgetRef ref) async {
    final myId = ref.read(meProvider).valueOrNull?.id;
    final pos = myId == null
        ? null
        : ref.read(liveTripProvider(tripId)).members[myId]?.position;
    final loc = pos == null
        ? ''
        : ' https://maps.google.com/?q=${pos.latitude},${pos.longitude}';
    await _send(context, ref, '📍 Regroup at my location.$loc');
  }

  Future<void> _send(BuildContext context, WidgetRef ref, String text) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      await repo.sendAnnouncement(tripId, text);
      messenger.showSnackBar(
          const SnackBar(content: Text('Broadcast sent to the pack')));
    } catch (e) {
      messenger
          .showSnackBar(SnackBar(content: Text('Could not broadcast: $e')));
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/widgets/user_avatar.dart';
import '../map/live_trip_controller.dart';
import '../profile/me_repository.dart';
import 'ready_check_repository.dart';
import 'trips_repository.dart';

/// Ready-check roster. Members toggle their own ready state; everyone sees the
/// live tally ("X of N ready") update as people tap in, driven by WS frames.
class ReadyCheckPanel extends ConsumerStatefulWidget {
  const ReadyCheckPanel({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<ReadyCheckPanel> createState() => _ReadyCheckPanelState();
}

class _ReadyCheckPanelState extends ConsumerState<ReadyCheckPanel> {
  bool _seeded = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tripAsync = ref.watch(tripDetailProvider(widget.tripId));
    final myId = ref.watch(meProvider).valueOrNull?.id;
    final ready = ref.watch(liveTripProvider(widget.tripId)).readyUserIds;

    // Seed the live set once from the REST snapshot.
    ref.listen(readyCheckProvider(widget.tripId), (_, next) {
      final snap = next.valueOrNull;
      if (snap != null && !_seeded) {
        _seeded = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref
              .read(liveTripProvider(widget.tripId).notifier)
              .seedReady(snap.readyUserIds);
        });
      }
    });
    // Ensure the provider is subscribed (triggers the listen above).
    ref.watch(readyCheckProvider(widget.tripId));

    final members = tripAsync.valueOrNull?.members ?? const [];
    final total = members.length;
    final readyCount = members.where((m) => ready.contains(m.userId)).length;
    final iAmReady = myId != null && ready.contains(myId);
    final allReady = total > 0 && readyCount == total;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  allReady ? Icons.check_circle : Icons.how_to_reg,
                  color: allReady ? const Color(0xFF2ECC71) : scheme.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  allReady ? 'Everyone is ready!' : 'Ready check',
                  style: textTheme.titleLarge,
                ),
                const Spacer(),
                Text(
                  '$readyCount / $total',
                  style: textTheme.titleMedium?.copyWith(
                    color: allReady ? const Color(0xFF2ECC71) : scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: AppRadii.full,
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : readyCount / total,
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
                color: allReady ? const Color(0xFF2ECC71) : scheme.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: members.length,
                itemBuilder: (_, i) {
                  final m = members[i];
                  final isReady = ready.contains(m.userId);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: UserAvatar(
                      name: m.label,
                      avatarUrl: m.avatarUrl,
                      radius: 18,
                    ),
                    title: Text(m.label),
                    trailing: Icon(
                      isReady
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: isReady
                          ? const Color(0xFF2ECC71)
                          : scheme.outline,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor:
                    iAmReady ? scheme.surfaceContainerHighest : null,
                foregroundColor: iAmReady ? scheme.onSurface : null,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              ),
              onPressed: _busy ? null : () => _toggle(!iAmReady),
              icon: Icon(iAmReady ? Icons.undo : Icons.check),
              label: Text(iAmReady ? "I'm not ready" : "I'm ready"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggle(bool on) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final myId = ref.read(meProvider).valueOrNull?.id;
    // Optimistic: reflect my own toggle immediately; the WS echo confirms it.
    if (myId != null) {
      final cur = Set<String>.from(
        ref.read(liveTripProvider(widget.tripId)).readyUserIds,
      );
      on ? cur.add(myId) : cur.remove(myId);
      ref.read(liveTripProvider(widget.tripId).notifier).seedReady(cur);
    }
    try {
      final repo = await ref.read(readyCheckRepositoryProvider.future);
      await repo.toggle(widget.tripId, on);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not update ready state: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

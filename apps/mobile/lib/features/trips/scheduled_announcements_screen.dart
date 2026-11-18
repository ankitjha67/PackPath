import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import 'scheduled_repository.dart';

/// Marshall screen: schedule announcements to fire automatically at a set time
/// (e.g. "Depart at 07:00"). A backend task posts them to the pack when due.
class ScheduledAnnouncementsScreen extends ConsumerWidget {
  const ScheduledAnnouncementsScreen({super.key, required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final async = ref.watch(tripScheduledProvider(tripId));
    final fmt = DateFormat('EEE d MMM, HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('Scheduled broadcasts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add_alarm),
        label: const Text('Schedule'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'No scheduled broadcasts. Queue one — it fires to the whole '
                  'pack automatically at the time you set.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.base),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) {
              final s = items[i];
              return Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: AppRadii.lg,
                ),
                child: ListTile(
                  leading: Icon(
                    s.sent ? Icons.check_circle : Icons.schedule,
                    color: s.sent ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  title: Text(s.body, style: textTheme.titleMedium),
                  subtitle: Text(
                      s.sent ? 'Sent' : 'Fires ${fmt.format(s.sendAt)}',
                      style: textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  trailing: s.sent
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _cancel(context, ref, s.id),
                        ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final bodyCtrl = TextEditingController();
    DateTime when = DateTime.now().add(const Duration(hours: 1));
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.base,
          right: AppSpacing.base,
          top: AppSpacing.base,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.base,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Schedule a broadcast',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: bodyCtrl,
                maxLength: 280,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Message',
                    hintText: 'e.g. Depart at 07:00 sharp'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(DateFormat('EEE d MMM, HH:mm').format(when)),
                trailing: const Icon(Icons.edit),
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: when,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (d == null) return;
                  if (!ctx.mounted) return;
                  final t = await showTimePicker(
                    context: ctx,
                    initialTime: TimeOfDay.fromDateTime(when),
                  );
                  if (t == null) return;
                  setSheet(() => when =
                      DateTime(d.year, d.month, d.day, t.hour, t.minute));
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Schedule'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true || bodyCtrl.text.trim().isEmpty) return;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(scheduledRepositoryProvider.future);
      await repo.create(
          tripId: tripId, body: bodyCtrl.text.trim(), sendAt: when);
      ref.invalidate(tripScheduledProvider(tripId));
      messenger
          .showSnackBar(const SnackBar(content: Text('Broadcast scheduled')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not schedule: $e')));
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, String id) async {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(scheduledRepositoryProvider.future);
      await repo.cancel(tripId: tripId, scheduledId: id);
      ref.invalidate(tripScheduledProvider(tripId));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not cancel: $e')));
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import 'notifications_repository.dart';

/// Phase 9 — notification settings. A master switch, per-category toggles, and
/// a quiet-hours window. Safety alerts (SOS/crash) always notify and so are
/// shown as always-on, not a toggle.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  NotificationPrefsDto? _prefs;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(notificationPrefsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 40),
                const SizedBox(height: AppSpacing.sm),
                Text('Could not load: $e', textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(notificationPrefsProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (loaded) {
          final p = _prefs ??= loaded;
          final on = p.enabled;
          return ListView(
            children: [
              SwitchListTile(
                title: const Text('Push notifications'),
                subtitle: const Text('Master switch for all non-safety pushes'),
                value: p.enabled,
                onChanged: (v) => _patch({'enabled': v}),
              ),
              const Divider(),
              _CategoryTile(
                label: 'Announcements',
                icon: Icons.campaign_outlined,
                value: p.announcements,
                enabled: on,
                onChanged: (v) => _patch({'announcements': v}),
              ),
              _CategoryTile(
                label: 'Nudges',
                icon: Icons.touch_app_outlined,
                value: p.nudges,
                enabled: on,
                onChanged: (v) => _patch({'nudges': v}),
              ),
              _CategoryTile(
                label: 'Detour votes',
                icon: Icons.alt_route,
                value: p.detours,
                enabled: on,
                onChanged: (v) => _patch({'detours': v}),
              ),
              _CategoryTile(
                label: 'Road hazards',
                icon: Icons.warning_amber_rounded,
                value: p.hazards,
                enabled: on,
                onChanged: (v) => _patch({'hazards': v}),
              ),
              _CategoryTile(
                label: 'Chat',
                icon: Icons.chat_bubble_outline,
                value: p.chat,
                enabled: on,
                onChanged: (v) => _patch({'chat': v}),
              ),
              _CategoryTile(
                label: 'Checklist',
                icon: Icons.checklist_rtl,
                value: p.checklist,
                enabled: on,
                onChanged: (v) => _patch({'checklist': v}),
              ),
              const Divider(),
              ListTile(
                leading: Icon(Icons.health_and_safety_outlined,
                    color: Theme.of(context).colorScheme.error),
                title: const Text('Safety alerts'),
                subtitle: const Text('SOS and crash alerts always notify you'),
                trailing: const Text('Always on'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.bedtime_outlined),
                title: const Text('Quiet hours'),
                subtitle: Text(
                  p.hasQuietHours
                      ? 'Silenced ${_fmt(p.quietStart!)}–${_fmt(p.quietEnd!)} '
                          '(UTC), except safety'
                      : 'Off — tap to set a nightly silent window',
                ),
                trailing: p.hasQuietHours
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _patch({'clear_quiet_hours': true}),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: _pickQuietHours,
              ),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          );
        },
      ),
    );
  }

  String _fmt(int hour) => '${hour.toString().padLeft(2, '0')}:00';

  Future<void> _pickQuietHours() async {
    final start = await showDialog<int>(
      context: context,
      builder: (_) => const _HourPickerDialog(title: 'Quiet hours start (UTC)'),
    );
    if (start == null || !mounted) return;
    final end = await showDialog<int>(
      context: context,
      builder: (_) => const _HourPickerDialog(title: 'Quiet hours end (UTC)'),
    );
    if (end == null || !mounted) return;
    _patch({'quiet_start': start, 'quiet_end': end});
  }

  Future<void> _patch(Map<String, dynamic> patch) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final repo = await ref.read(notificationsRepositoryProvider.future);
      final updated = await repo.update(patch);
      if (!mounted) return;
      setState(() => _prefs = updated);
      ref.invalidate(notificationPrefsProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.label,
    required this.icon,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(icon),
      title: Text(label),
      value: value && enabled,
      onChanged: enabled ? onChanged : null,
    );
  }
}

class _HourPickerDialog extends StatelessWidget {
  const _HourPickerDialog({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        height: 320,
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 6,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
          ),
          itemCount: 24,
          itemBuilder: (_, h) => OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
            ),
            onPressed: () => Navigator.pop(context, h),
            child: Text(h.toString().padLeft(2, '0')),
          ),
        ),
      ),
    );
  }
}

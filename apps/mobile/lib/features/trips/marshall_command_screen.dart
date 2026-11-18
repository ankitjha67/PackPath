import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/kinetic_path_tokens.dart';
import '../../shared/models/trip.dart';
import '../../shared/models/waypoint.dart';
import '../chat/chat_repository.dart';
import '../map/live_trip_controller.dart';
import '../profile/me_repository.dart';
import 'ready_check_panel.dart';
import 'trips_repository.dart';
import 'waypoints_repository.dart';

/// Pack roles the marshall can assign, with display labels + icons.
const _roles = <String, (String, IconData)>{
  'driver': ('Driver', Icons.drive_eta),
  'navigator': ('Navigator', Icons.explore),
  'dj': ('DJ', Icons.headphones),
  'photographer': ('Photographer', Icons.photo_camera),
  'treasurer': ('Treasurer', Icons.account_balance_wallet),
  'member': ('Member', Icons.person),
};

/// Stop categories with icons.
const _categories = <String, (String, IconData)>{
  'fuel': ('Fuel', Icons.local_gas_station),
  'food': ('Food', Icons.restaurant),
  'rest': ('Rest', Icons.local_cafe),
  'viewpoint': ('Viewpoint', Icons.photo_camera_outlined),
  'overnight': ('Overnight', Icons.hotel),
  'repair': ('Repair', Icons.build),
  'checkpoint': ('Checkpoint', Icons.flag),
  'other': ('Other', Icons.place),
};

/// Marshall Command — the pack marshall's control center: live readiness, a
/// route/stops builder (reorder, categorise, assign an owner, notes, lock), a
/// roster with role assignment, and the broadcast/regroup/ready commands.
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
    final waypoints = ref.watch(tripWaypointsProvider(tripId)).valueOrNull ??
        const <WaypointDto>[];

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
          final nameOf = {
            for (final m in trip.members) m.userId: m.label,
          };
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
                    Text(
                        '${live.onlineUserIds.length} online · '
                        '${waypoints.length} stops',
                        style: textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9))),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Route builder ──────────────────────────────────────────
              Row(
                children: [
                  Text('ROUTE & STOPS',
                      style: textTheme.labelMedium?.copyWith(
                          letterSpacing: 1.5, color: scheme.onSurfaceVariant)),
                  const Spacer(),
                  Icon(trip.routeLocked ? Icons.lock : Icons.lock_open,
                      size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('Lock',
                      style: textTheme.labelMedium
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  Switch(
                    value: trip.routeLocked,
                    onChanged: (v) => _setLock(context, ref, v),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              if (waypoints.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Text(
                    'No stops yet. Long-press the map to drop one, then come '
                    'back to order and assign them.',
                    style: textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                )
              else
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: !trip.routeLocked,
                  itemCount: waypoints.length,
                  onReorder: (oldI, newI) =>
                      _reorder(context, ref, waypoints, oldI, newI),
                  itemBuilder: (context, i) {
                    final wp = waypoints[i];
                    final cat = _categories[wp.category];
                    return Container(
                      key: ValueKey(wp.id),
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: AppRadii.lg,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: scheme.primaryContainer,
                          child: Text('${i + 1}',
                              style: TextStyle(
                                  color: scheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold)),
                        ),
                        title: Text(wp.name, style: textTheme.titleMedium),
                        subtitle: Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (cat != null) _chip(context, cat.$2, cat.$1),
                            if (wp.assigneeId != null)
                              _chip(context, Icons.person,
                                  nameOf[wp.assigneeId] ?? 'Assigned'),
                            if (wp.notes != null && wp.notes!.isNotEmpty)
                              Text(wp.notes!,
                                  style: textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant)),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: trip.routeLocked
                              ? null
                              : () => _editStop(context, ref, wp, trip),
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: AppSpacing.lg),

              // ── Roster & roles ─────────────────────────────────────────
              Text('PACK ROSTER',
                  style: textTheme.labelMedium?.copyWith(
                      letterSpacing: 1.5, color: scheme.onSurfaceVariant)),
              const SizedBox(height: AppSpacing.sm),
              for (final m in trip.members)
                _memberTile(context, ref, m, live, myId),
              const SizedBox(height: AppSpacing.lg),

              // ── Commands ───────────────────────────────────────────────
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

  Widget _chip(BuildContext context, IconData icon, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: AppRadii.full,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _memberTile(BuildContext context, WidgetRef ref, TripMemberDto m,
      LiveTripState live, String? myId) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final online = live.onlineUserIds.contains(m.userId);
    final ready = live.readyUserIds.contains(m.userId);
    final roleMeta = _roles[m.role] ?? ('Member', Icons.person);
    final isOwner = m.role == 'owner';
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadii.lg,
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _hex(m.color),
          child: Text(m.label.characters.first.toUpperCase(),
              style: const TextStyle(color: Colors.white)),
        ),
        title: Text(m.label, style: textTheme.titleMedium),
        subtitle: Row(
          children: [
            Icon(online ? Icons.circle : Icons.circle_outlined,
                size: 10, color: online ? Colors.green : scheme.outline),
            const SizedBox(width: 4),
            Text(online ? 'online' : 'offline',
                style: textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            if (ready) ...[
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.check_circle, size: 12, color: scheme.primary),
              const SizedBox(width: 2),
              Text('ready',
                  style: textTheme.bodySmall?.copyWith(color: scheme.primary)),
            ],
          ],
        ),
        trailing: isOwner
            ? _chip(context, Icons.military_tech, 'Marshall')
            : ActionChip(
                avatar: Icon(roleMeta.$2, size: 16),
                label: Text(roleMeta.$1),
                onPressed: () => _assignRole(context, ref, m),
              ),
      ),
    );
  }

  Future<void> _assignRole(
      BuildContext context, WidgetRef ref, TripMemberDto m) async {
    final role = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Text('Assign role to ${m.label}',
                    style: Theme.of(ctx).textTheme.titleMedium),
              ),
              for (final e in _roles.entries)
                ListTile(
                  leading: Icon(e.value.$2),
                  title: Text(e.value.$1),
                  trailing: m.role == e.key ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(ctx, e.key),
                ),
            ],
          ),
        ),
      ),
    );
    if (role == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(tripsRepositoryProvider.future);
      await repo.assignRole(tripId: tripId, userId: m.userId, role: role);
      ref.invalidate(tripDetailProvider(tripId));
      messenger.showSnackBar(
          SnackBar(content: Text('${m.label} is now ${_roles[role]!.$1}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not assign: $e')));
    }
  }

  Future<void> _setLock(BuildContext context, WidgetRef ref, bool v) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(tripsRepositoryProvider.future);
      await repo.setRouteLock(tripId: tripId, locked: v);
      ref.invalidate(tripDetailProvider(tripId));
      messenger.showSnackBar(
          SnackBar(content: Text(v ? 'Route locked' : 'Route unlocked')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not update: $e')));
    }
  }

  Future<void> _reorder(BuildContext context, WidgetRef ref,
      List<WaypointDto> waypoints, int oldI, int newI) async {
    final ids = waypoints.map((w) => w.id).toList();
    if (newI > oldI) newI -= 1;
    final moved = ids.removeAt(oldI);
    ids.insert(newI, moved);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(waypointsRepositoryProvider.future);
      await repo.reorder(tripId: tripId, orderedIds: ids);
      ref.invalidate(tripWaypointsProvider(tripId));
      ref.invalidate(tripRouteProvider(tripId));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not reorder: $e')));
    }
  }

  Future<void> _editStop(
      BuildContext context, WidgetRef ref, WaypointDto wp, TripDto trip) async {
    final nameCtrl = TextEditingController(text: wp.name);
    final notesCtrl = TextEditingController(text: wp.notes ?? '');
    String? category = wp.category;
    String? assignee = wp.assigneeId;
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
              Text('Edit stop', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('Category', style: Theme.of(ctx).textTheme.labelMedium),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (final e in _categories.entries)
                    ChoiceChip(
                      avatar: Icon(e.value.$2, size: 16),
                      label: Text(e.value.$1),
                      selected: category == e.key,
                      onSelected: (s) =>
                          setSheet(() => category = s ? e.key : null),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('Stop owner', style: Theme.of(ctx).textTheme.labelMedium),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  ChoiceChip(
                    label: const Text('Unassigned'),
                    selected: assignee == null,
                    onSelected: (_) => setSheet(() => assignee = null),
                  ),
                  for (final m in trip.members)
                    ChoiceChip(
                      label: Text(m.label),
                      selected: assignee == m.userId,
                      onSelected: (s) =>
                          setSheet(() => assignee = s ? m.userId : null),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: notesCtrl,
                maxLength: 500,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Notes', hintText: 'e.g. diesel only, ATM here'),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Save')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(waypointsRepositoryProvider.future);
      await repo.update(
        tripId: tripId,
        waypointId: wp.id,
        name: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
        category: category,
        notes: notesCtrl.text.trim(),
        assigneeId: assignee,
      );
      ref.invalidate(tripWaypointsProvider(tripId));
      messenger.showSnackBar(const SnackBar(content: Text('Stop updated')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not update: $e')));
    }
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

  static Color _hex(String value) {
    final hex = value.replaceAll('#', '');
    final v = int.tryParse(hex, radix: 16) ?? 0x888888;
    return Color(0xFF000000 | v);
  }
}

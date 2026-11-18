import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/kinetic_path_tokens.dart';
import '../../shared/models/trip.dart';
import '../../shared/widgets/user_avatar.dart';
import '../logistics/checklist_repository.dart';
import '../map/live_trip_controller.dart';
import 'trips_repository.dart';

/// Mission Briefing — the `designs/mission_briefing` "pre-departure protocol"
/// flow. Aggregates the trip name, launch countdown, pack manifest (live
/// online state + roles) and gear verification (the shared checklist) into one
/// go/no-go screen, ending in an "Engage Mission" CTA into the live HUD.
class MissionBriefingScreen extends ConsumerWidget {
  const MissionBriefingScreen({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripAsync = ref.watch(tripDetailProvider(tripId));
    final live = ref.watch(liveTripProvider(tripId));
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<KineticPathTokens>()!;

    return Scaffold(
      appBar: AppBar(title: const Text('Mission briefing')),
      body: tripAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
        data: (trip) {
          final checklist = live.checklist.values
              .map((e) => ChecklistItemDto.fromJson(e))
              .toList();
          final gearDone = checklist.where((c) => c.done).length;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.base),
            children: [
              Text(
                'PRE-DEPARTURE PROTOCOL',
                style: textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                trip.name.toUpperCase(),
                style: textTheme.displaySmall
                    ?.copyWith(fontWeight: FontWeight.w700, height: 1.05),
              ),
              const SizedBox(height: AppSpacing.md),
              _StatusLaunch(trip: trip),
              const SizedBox(height: AppSpacing.lg),
              _SectionCard(
                label: 'PACK MANIFEST',
                trailing: _Chip(
                  '${live.onlineUserIds.length}/${trip.members.length} ACTIVE',
                  bg: scheme.secondary,
                  fg: scheme.onSecondary,
                ),
                child: Column(
                  children: [
                    for (final m in trip.members)
                      _ManifestRow(
                        member: m,
                        online: live.onlineUserIds.contains(m.userId),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              _SectionCard(
                label: 'GEAR VERIFICATION',
                trailing: Icon(
                  gearDone == checklist.length && checklist.isNotEmpty
                      ? Icons.verified
                      : Icons.warning_amber_rounded,
                  color: gearDone == checklist.length && checklist.isNotEmpty
                      ? Colors.green
                      : scheme.tertiary,
                ),
                child: checklist.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Text(
                          'No gear items yet — add them in Checklist.',
                          style: textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      )
                    : Column(
                        children: [
                          for (final c in checklist)
                            _GearRow(item: c, tripId: tripId),
                        ],
                      ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Container(
                decoration: BoxDecoration(
                  gradient: tokens.ctaGradient,
                  borderRadius: AppRadii.full,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: AppRadii.full,
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.base),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'ENGAGE MISSION',
                            style: textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              letterSpacing: 2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          const Icon(
                            Icons.rocket_launch,
                            color: Colors.white,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'All GPS streams synchronize upon engagement.',
                textAlign: TextAlign.center,
                style: textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 1,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatusLaunch extends StatelessWidget {
  const _StatusLaunch({required this.trip});
  final TripDto trip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadii.full,
      ),
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Row(
        children: [
          Expanded(
            child: _kv(
              'STATUS',
              _statusLabel(trip.status),
              valueColor: scheme.primary,
            ),
          ),
          Container(width: 1, height: 36, color: scheme.surfaceContainerHigh),
          Expanded(child: _kv('LAUNCH', _launch(trip.startAt))),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, {Color? valueColor}) => Builder(
        builder: (c) {
          final t = Theme.of(c).textTheme;
          return Column(
            children: [
              Text(
                k,
                style: t.labelSmall?.copyWith(
                  letterSpacing: 1.2,
                  color: Theme.of(c).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(v, style: t.titleMedium?.copyWith(color: valueColor)),
            ],
          );
        },
      );

  static String _statusLabel(String s) {
    switch (s) {
      case 'planned':
        return 'Final Prep';
      case 'active':
        return 'Underway';
      case 'ended':
        return 'Complete';
      default:
        return s;
    }
  }

  static String _launch(DateTime? dt) {
    if (dt == null) return 'TBD';
    final diff = dt.difference(DateTime.now());
    if (diff.isNegative) return 'Departed';
    if (diff.inHours >= 24) return 'T-${diff.inDays}d';
    if (diff.inHours >= 1) return 'T-${diff.inHours}h';
    return 'T-${diff.inMinutes}m';
  }
}

class _ManifestRow extends StatelessWidget {
  const _ManifestRow({required this.member, required this.online});
  final TripMemberDto member;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Stack(
            children: [
              UserAvatar(
                name: member.displayName ?? 'Member',
                avatarUrl: member.avatarUrl,
                radius: 20,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: online ? Colors.green : scheme.outline,
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: scheme.surfaceContainerLow, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.displayName ?? 'Member',
                  style: textTheme.titleSmall,
                ),
                Text(
                  member.role.toUpperCase(),
                  style: textTheme.labelSmall?.copyWith(
                    letterSpacing: 1,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            online ? Icons.check_circle : Icons.circle_outlined,
            color: online ? Colors.green : scheme.outline,
            size: 22,
          ),
        ],
      ),
    );
  }
}

class _GearRow extends ConsumerWidget {
  const _GearRow({required this.item, required this.tripId});
  final ChecklistItemDto item;
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: AppRadii.xl,
      onTap: () async {
        try {
          final repo =
              await ref.read(checklistRepositoryProvider(tripId).future);
          final dto = await repo.toggle(item.id);
          ref
              .read(liveTripProvider(tripId).notifier)
              .upsertChecklist(dto.toJson());
        } catch (_) {}
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              item.done ? Icons.check_circle : Icons.radio_button_unchecked,
              color: item.done ? scheme.primary : scheme.outline,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                item.qty > 1 ? '${item.title}  ×${item.qty}' : item.title,
                style: textTheme.titleSmall?.copyWith(
                  decoration: item.done ? TextDecoration.lineThrough : null,
                  color: item.done ? scheme.onSurfaceVariant : null,
                ),
              ),
            ),
            if (!item.done)
              Text(
                'VERIFY',
                style: textTheme.labelSmall
                    ?.copyWith(color: scheme.tertiary, letterSpacing: 1),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.label, required this.child, this.trailing});
  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadii.full,
      ),
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                label,
                style: textTheme.labelMedium?.copyWith(
                  letterSpacing: 1.2,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {required this.bg, required this.fg});
  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadii.full),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: fg, letterSpacing: 0.8),
      ),
    );
  }
}

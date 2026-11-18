import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/models/member_location.dart';
import '../../shared/models/trip.dart';
import '../../shared/widgets/user_avatar.dart';
import '../map/live_trip_controller.dart';
import '../trips/pack_cohesion.dart';
import '../trips/trips_repository.dart';

/// Pack Health — the `designs/safety_health_monitor` HUD, adapted to the real
/// telemetry PackPath collects (battery, pace, online state, stragglers, active
/// alerts) instead of biometric heart-rate data. One card per member with a
/// battery bar + pace/signal tiles, a group summary, and the active SOS feed.
class PackHealthScreen extends ConsumerWidget {
  const PackHealthScreen({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripAsync = ref.watch(tripDetailProvider(tripId));
    final live = ref.watch(liveTripProvider(tripId));
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final cohesion = computeCohesion(live.members);

    return Scaffold(
      appBar: AppBar(title: const Text('Pack health')),
      body: tripAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
        data: (trip) {
          final batteries = live.members.values
              .map((m) => m.battery)
              .whereType<int>()
              .toList();
          final avgBattery = batteries.isEmpty
              ? null
              : batteries.reduce((a, b) => a + b) ~/ batteries.length;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.base),
            children: [
              if (live.activeSafetyAlert != null)
                _AlertBanner(alert: live.activeSafetyAlert!),
              Row(
                children: [
                  Text('Pack Health', style: textTheme.headlineSmall),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.secondary,
                      borderRadius: AppRadii.full,
                    ),
                    child: Text('${trip.members.length} MEMBERS',
                        style: textTheme.labelSmall?.copyWith(
                            color: scheme.onSecondary, letterSpacing: 0.8)),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              for (final m in trip.members)
                _MemberHealthCard(
                  member: m,
                  loc: live.members[m.userId],
                  online: live.onlineUserIds.contains(m.userId),
                  straggler: cohesion.stragglerIds.contains(m.userId),
                  status: live.memberStatus[m.userId],
                ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: AppRadii.full,
                ),
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('PACK BATTERY',
                            style: textTheme.labelSmall?.copyWith(
                                letterSpacing: 1.2,
                                color: scheme.onSurfaceVariant)),
                        Text(avgBattery == null ? '—' : '$avgBattery%',
                            style: textTheme.displaySmall),
                      ],
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                            '${cohesion.stragglerIds.length} straggler'
                            '${cohesion.stragglerIds.length == 1 ? '' : 's'}',
                            style: textTheme.titleMedium?.copyWith(
                                color: cohesion.stragglerIds.isEmpty
                                    ? Colors.green
                                    : scheme.tertiary)),
                        Text('${live.onlineUserIds.length} online',
                            style: textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AlertBanner extends StatelessWidget {
  const _AlertBanner({required this.alert});
  final Map<String, dynamic> alert;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.base),
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: AppRadii.full,
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: scheme.error),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SAFETY ALERT ACTIVE',
                    style: textTheme.labelMedium?.copyWith(
                        color: scheme.onErrorContainer, letterSpacing: 1)),
                Text('${alert['kind'] ?? 'safety'} — open the map to respond.',
                    style: textTheme.bodySmall
                        ?.copyWith(color: scheme.onErrorContainer)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberHealthCard extends StatelessWidget {
  const _MemberHealthCard({
    required this.member,
    required this.loc,
    required this.online,
    required this.straggler,
    required this.status,
  });

  final TripMemberDto member;
  final MemberLocation? loc;
  final bool online;
  final bool straggler;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final battery = loc?.battery;
    final paceKmh =
        loc?.speed != null && loc!.speed! > 0 ? (loc!.speed! * 3.6) : 0.0;
    final critical = straggler || (battery != null && battery <= 15);
    final barColor = critical
        ? scheme.error
        : (battery != null && battery <= 35
            ? scheme.tertiary
            : scheme.secondary);
    final stateLabel = !online
        ? 'OFFLINE'
        : straggler
            ? 'FALLING BEHIND'
            : (status == null ? 'IN FORMATION' : status!.toUpperCase());

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadii.full,
        border: critical
            ? Border.all(color: scheme.error.withValues(alpha: 0.5), width: 1.5)
            : null,
      ),
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(
                  name: member.displayName ?? 'Member',
                  avatarUrl: member.avatarUrl,
                  radius: 22),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(member.displayName ?? 'Member',
                        style: textTheme.titleMedium),
                    Text(stateLabel,
                        style: textTheme.labelSmall?.copyWith(
                          letterSpacing: 1,
                          color: critical ? scheme.error : scheme.secondary,
                        )),
                  ],
                ),
              ),
              Icon(online ? Icons.sensors : Icons.sensors_off,
                  color: online ? scheme.secondary : scheme.outline, size: 20),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Text('BATTERY',
                  style: textTheme.labelSmall?.copyWith(
                      letterSpacing: 1, color: scheme.onSurfaceVariant)),
              const Spacer(),
              Text(battery == null ? '—' : '$battery%',
                  style: textTheme.titleMedium?.copyWith(color: barColor)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: AppRadii.lg,
            child: LinearProgressIndicator(
              value: battery == null ? 0 : battery / 100,
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHigh,
              color: barColor,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _tile(context, 'PACE',
                    paceKmh > 0 ? '${paceKmh.round()} km/h' : 'stopped'),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _tile(context, 'SIGNAL', online ? 'live' : 'lost'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, String k, String v) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: AppRadii.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k,
              style: textTheme.labelSmall
                  ?.copyWith(letterSpacing: 1, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(v, style: textTheme.titleMedium),
        ],
      ),
    );
  }
}

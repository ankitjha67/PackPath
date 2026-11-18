import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/kinetic_path_tokens.dart';
import '../../shared/models/trip.dart';
import '../../shared/widgets/user_avatar.dart';
import 'trips_repository.dart';

/// Home / Lobby — the editorial "Assemble your Pack" screen from
/// `designs/detailed_pack_lobby`. A gradient create-pack hero, scan-to-join,
/// an upcoming-packs carousel, an active-pack HUD bar, and past expeditions,
/// all on the Kinetic Path design system.
class TripListScreen extends ConsumerWidget {
  const TripListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(myTripsProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(myTripsProvider),
          child: tripsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Text('Could not load your packs:\n$err'),
                ),
              ],
            ),
            data: (trips) {
              final active = trips
                  .where((t) => t.status != 'ended' && t.status != 'cancelled')
                  .toList();
              final past = trips
                  .where((t) => t.status == 'ended' || t.status == 'cancelled')
                  .toList();
              return ListView(
                padding: EdgeInsets.zero,
                children: [
                  const _BrandBar(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.base,
                      AppSpacing.sm,
                      AppSpacing.base,
                      AppSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Editorial headline — "Pack." in the brand colour.
                        RichText(
                          text: TextSpan(
                            style: textTheme.displaySmall
                                ?.copyWith(color: scheme.onSurface),
                            children: [
                              const TextSpan(text: 'Assemble your '),
                              TextSpan(
                                text: 'Pack.',
                                style: TextStyle(color: scheme.primary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Coordinate waypoints, share live telemetry, and '
                          'never lose your trail partners.',
                          style: textTheme.bodyLarge
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        const _CreatePackHero(),
                        const SizedBox(height: AppSpacing.base),
                        const _ScanToJoinCard(),
                        const SizedBox(height: AppSpacing.xl),
                        _UpcomingPacks(active: active),
                        if (past.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xl),
                          _PastExpeditions(past: past),
                        ],
                        const SizedBox(height: 96),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      bottomSheet: tripsAsync.maybeWhen(
        data: (trips) {
          final active = trips
              .where((t) => t.status != 'ended' && t.status != 'cancelled')
              .toList();
          if (active.isEmpty) return null;
          return _ActivePackBar(trip: active.first);
        },
        orElse: () => null,
      ),
    );
  }
}

class _BrandBar extends StatelessWidget {
  const _BrandBar();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.md,
        AppSpacing.base,
        0,
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: AppRadii.xl,
            child: Image.asset('assets/icon/icon.png', width: 36, height: 36),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'PackPath',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => context.push('/me'),
            icon: const Icon(Icons.account_circle_outlined, size: 30),
            tooltip: 'Profile',
          ),
          IconButton(
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _CreatePackHero extends StatelessWidget {
  const _CreatePackHero();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KineticPathTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        gradient: tokens.ctaGradient,
        borderRadius: AppRadii.full,
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: Colors.white,
            radius: 22,
            child: Icon(
              Icons.add,
              color: Theme.of(context).colorScheme.primary,
              size: 26,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Create New Pack',
            style: textTheme.headlineSmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            'Start a fresh expedition and invite your team.',
            style: textTheme.bodyMedium
                ?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Theme.of(context).colorScheme.primary,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              shape: const RoundedRectangleBorder(borderRadius: AppRadii.xl),
            ),
            onPressed: () => context.push('/trips/new'),
            icon: const Text(
              'Initialize Mission',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            label: const Icon(Icons.arrow_forward, size: 18),
          ),
        ],
      ),
    );
  }
}

class _ScanToJoinCard extends StatelessWidget {
  const _ScanToJoinCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadii.full,
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: AppRadii.xl,
            ),
            child: Icon(Icons.qr_code_2, size: 56, color: scheme.secondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Scan to Join', style: textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Found a teammate? Scan their Pack ID to sync.',
            textAlign: TextAlign.center,
            style:
                textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: () => context.push('/trips/join'),
            child: Text(
              'OPEN CAMERA',
              style: textTheme.labelLarge?.copyWith(
                color: scheme.secondary,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingPacks extends StatelessWidget {
  const _UpcomingPacks({required this.active});
  final List<TripDto> active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Upcoming Packs', style: textTheme.headlineSmall),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: AppRadii.full,
              ),
              child: Text(
                '${active.length} ACTIVE',
                style: textTheme.labelMedium?.copyWith(
                  letterSpacing: 1,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (active.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: AppRadii.full,
            ),
            child: Text(
              'No active packs yet. Create one or scan to join.',
              style: textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          )
        else
          SizedBox(
            height: 196,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: active.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
              itemBuilder: (_, i) => _PackCard(trip: active[i]),
            ),
          ),
      ],
    );
  }
}

class _PackCard extends StatelessWidget {
  const _PackCard({required this.trip});
  final TripDto trip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final members = trip.members;
    return GestureDetector(
      onTap: () => context.push('/trips/${trip.id}'),
      child: Container(
        width: 300,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: AppRadii.full,
        ),
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _AvatarStack(members: members),
                const Spacer(),
                Icon(Icons.group, size: 16, color: scheme.secondary),
                const SizedBox(width: 4),
                Text(
                  '${members.length} Members',
                  style:
                      textTheme.labelLarge?.copyWith(color: scheme.secondary),
                ),
              ],
            ),
            const Spacer(),
            Text(
              trip.name,
              style: textTheme.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.place_outlined,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  trip.status.toUpperCase(),
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DEPARTURE',
                      style: textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.2,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(_departure(trip.startAt), style: textTheme.titleSmall),
                  ],
                ),
                const Spacer(),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: AppRadii.xl,
                  ),
                  child: Icon(Icons.chevron_right, color: scheme.onSurface),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.members});
  final List<TripMemberDto> members;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = members.take(2).toList();
    final extra = members.length - shown.length;
    return SizedBox(
      width: 34.0 * shown.length + (extra > 0 ? 30 : 0) + 8,
      height: 36,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * 26.0,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: scheme.surfaceContainerLowest,
                    width: 2,
                  ),
                ),
                child: UserAvatar(
                  name: shown[i].displayName ?? 'Member',
                  avatarUrl: shown[i].avatarUrl,
                  radius: 16,
                ),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * 26.0,
              child: CircleAvatar(
                radius: 16,
                backgroundColor: scheme.secondaryContainer,
                child: Text(
                  '+$extra',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PastExpeditions extends StatelessWidget {
  const _PastExpeditions({required this.past});
  final List<TripDto> past;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Past expeditions', style: textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.md),
        for (final t in past)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Material(
              color: scheme.surfaceContainerLow,
              borderRadius: AppRadii.full,
              child: InkWell(
                borderRadius: AppRadii.full,
                onTap: () => context.push('/trips/${t.id}'),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: Row(
                    children: [
                      Icon(Icons.history, color: scheme.onSurfaceVariant),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.name, style: textTheme.titleMedium),
                            Text(
                              '${t.status.toUpperCase()} · '
                              '${t.members.length} member'
                              '${t.members.length == 1 ? '' : 's'}',
                              style: textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ActivePackBar extends StatelessWidget {
  const _ActivePackBar({required this.trip});
  final TripDto trip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: AppRadii.full,
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 10, color: scheme.secondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ACTIVE PACK',
                  style: textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2,
                    color: scheme.secondary,
                  ),
                ),
                Text(
                  trip.name,
                  style: textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          CircleAvatar(
            radius: 14,
            backgroundColor: scheme.secondary,
            child: Text(
              '${trip.members.length}',
              style: TextStyle(
                color: scheme.onSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.secondary,
              foregroundColor: scheme.onSecondary,
              shape: const RoundedRectangleBorder(borderRadius: AppRadii.xl),
            ),
            onPressed: () => context.push('/trips/${trip.id}'),
            child: const Text('ENTER HUD'),
          ),
        ],
      ),
    );
  }
}

String _departure(DateTime? dt) {
  if (dt == null) return 'TBD';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = dt.toLocal();
  final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final ampm = local.hour < 12 ? 'AM' : 'PM';
  final m = local.minute.toString().padLeft(2, '0');
  return '${months[local.month - 1]} ${local.day}, $h:$m $ampm';
}

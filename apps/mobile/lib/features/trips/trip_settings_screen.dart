import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/models/trip.dart';
import '../profile/me_repository.dart';
import 'trips_repository.dart';

/// Per-trip admin actions. Owner can end the trip; members can leave.
///
/// Rename and kick-member are intentionally read-only placeholders —
/// the backend does not yet expose PATCH /trips/:id or DELETE
/// /trips/:id/members/:userId. Those buttons show a "Coming in
/// Session 4" SnackBar instead of calling fake endpoints.
class TripSettingsScreen extends ConsumerStatefulWidget {
  const TripSettingsScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<TripSettingsScreen> createState() => _TripSettingsScreenState();
}

class _TripSettingsScreenState extends ConsumerState<TripSettingsScreen> {
  bool _busy = false;

  Future<void> _leave(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave this trip?'),
        content: const Text(
          'You will stop sharing your location and your chat history '
          'for this trip stays with the pack. You can rejoin with the '
          'same code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.onError,
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(tripsRepositoryProvider.future);
      await repo.leave(widget.tripId);
      ref.invalidate(myTripsProvider);
      ref.invalidate(tripDetailProvider(widget.tripId));
      if (!context.mounted) return;
      context.go('/trips');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not leave trip: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _end(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End this trip for everyone?'),
        content: const Text(
          'Location sharing stops for all members. The recap is still '
          'accessible. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.onError,
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('End trip'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(tripsRepositoryProvider.future);
      await repo.end(widget.tripId);
      ref.invalidate(myTripsProvider);
      ref.invalidate(tripDetailProvider(widget.tripId));
      if (!context.mounted) return;
      context.go('/trips');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not end trip: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notYetAvailable(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature — coming in Session 4.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tripAsync = ref.watch(tripDetailProvider(widget.tripId));
    final meAsync = ref.watch(meProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Trip settings')),
      body: tripAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(tripDetailProvider(widget.tripId)),
        ),
        data: (trip) {
          final isOwner = meAsync.maybeWhen(
            data: (me) => me.id == trip.ownerId,
            orElse: () => false,
          );
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.base),
            children: [
              const _SectionHeader(label: 'ABOUT THIS TRIP'),
              _AboutGroup(trip: trip),
              const SizedBox(height: AppSpacing.md),
              const _SectionHeader(label: 'MEMBERS'),
              _MembersGroup(
                trip: trip,
                isOwner: isOwner,
                onKickTapped: () => _notYetAvailable('Kicking members'),
              ),
              const SizedBox(height: AppSpacing.md),
              const _SectionHeader(label: 'DANGER ZONE'),
              _DangerZone(
                isOwner: isOwner,
                busy: _busy,
                onLeave: () => _leave(context),
                onEnd: () => _end(context),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.primary,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _AboutGroup extends StatelessWidget {
  const _AboutGroup({required this.trip});
  final TripDto trip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: AppRadii.lg,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NAME', style: _labelStyle(context)),
          const SizedBox(height: AppSpacing.xs),
          Text(trip.name, style: textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          Text('CODE', style: _labelStyle(context)),
          const SizedBox(height: AppSpacing.xs),
          InkWell(
            borderRadius: AppRadii.lg,
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: trip.joinCode));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Code copied')),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Text(
                    trip.joinCode,
                    style: textTheme.titleMedium?.copyWith(
                      letterSpacing: 4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    Icons.copy,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('STATUS', style: _labelStyle(context)),
          const SizedBox(height: AppSpacing.xs),
          Text(trip.status.toUpperCase(), style: textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.md),
          Text('MEMBERS', style: _labelStyle(context)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${trip.members.length} in the pack',
            style: textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  TextStyle? _labelStyle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          letterSpacing: 1.0,
          fontWeight: FontWeight.w700,
        );
  }
}

class _MembersGroup extends StatelessWidget {
  const _MembersGroup({
    required this.trip,
    required this.isOwner,
    required this.onKickTapped,
  });

  final TripDto trip;
  final bool isOwner;
  final VoidCallback onKickTapped;

  static Color _hex(String value) {
    final hex = value.replaceAll('#', '');
    final v = int.parse(hex, radix: 16);
    return Color(0xFF000000 | v);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: AppRadii.lg,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < trip.members.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: _hex(trip.members[i].color),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          trip.members[i].userId.substring(0, 8),
                          style: textTheme.titleSmall,
                        ),
                        Text(
                          trip.members[i].role.toUpperCase(),
                          style: textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isOwner && trip.members[i].role != 'owner')
                    IconButton(
                      tooltip: 'Remove from trip',
                      icon: const Icon(Icons.person_remove_outlined),
                      color: scheme.error,
                      onPressed: onKickTapped,
                    ),
                ],
              ),
            ),
            if (i < trip.members.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                indent: AppSpacing.lg + AppSpacing.sm,
                color: scheme.surfaceContainerHighest,
              ),
          ],
        ],
      ),
    );
  }
}

class _DangerZone extends StatelessWidget {
  const _DangerZone({
    required this.isOwner,
    required this.busy,
    required this.onLeave,
    required this.onEnd,
  });

  final bool isOwner;
  final bool busy;
  final VoidCallback onLeave;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: AppRadii.lg,
        border: Border.all(
          color: scheme.error.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isOwner
                ? 'Ending the trip stops location sharing for every '
                    'member. The recap is still accessible after. '
                    'This cannot be undone.'
                : 'Leaving the trip stops your location from being '
                    'shared with the pack. You can rejoin with the '
                    'same code.',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              foregroundColor: scheme.onError,
              backgroundColor: scheme.error,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            ),
            onPressed: busy ? null : (isOwner ? onEnd : onLeave),
            icon: busy
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(isOwner ? Icons.stop_circle_outlined : Icons.logout),
            label: Text(
              isOwner ? 'End trip for everyone' : 'Leave trip',
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: scheme.error),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Could not load trip settings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

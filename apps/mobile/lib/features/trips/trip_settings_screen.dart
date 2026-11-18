import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/models/trip.dart';
import '../../shared/widgets/user_avatar.dart';
import '../contacts/contacts_repository.dart';
import '../contacts/member_profile_screen.dart';
import '../map/live_trip_controller.dart';
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
  String _memberQuery = '';

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

  Future<void> _kickMember(
      BuildContext context, String userId, String label) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text(
          'Remove $label from this trip? They can rejoin with the trip code.',
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
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final repo = await ref.read(tripsRepositoryProvider.future);
      await repo.removeMember(tripId: widget.tripId, userId: userId);
      ref.invalidate(tripDetailProvider(widget.tripId));
      messenger.showSnackBar(SnackBar(content: Text('Removed $label')));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not remove member: $e')),
      );
    }
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
              ...ref.watch(incomingRequestsProvider(widget.tripId)).maybeWhen(
                    data: (reqs) => reqs.isEmpty
                        ? const <Widget>[]
                        : [
                            const _SectionHeader(label: 'CONNECTION REQUESTS'),
                            _IncomingRequests(tripId: trip.id, requests: reqs),
                            const SizedBox(height: AppSpacing.md),
                          ],
                    orElse: () => const <Widget>[],
                  ),
              const _SectionHeader(label: 'MEMBERS'),
              if (trip.members.length > 8)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: TextField(
                    onChanged: (v) => setState(() => _memberQuery = v),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search members',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: AppRadii.lg,
                      ),
                    ),
                  ),
                ),
              _MembersGroup(
                trip: trip,
                isOwner: isOwner,
                query: _memberQuery,
                onlineUserIds:
                    ref.watch(liveTripProvider(widget.tripId)).onlineUserIds,
                onKick: (userId, label) => _kickMember(context, userId, label),
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
    required this.onKick,
    this.onlineUserIds = const {},
    this.query = '',
  });

  final TripDto trip;
  final bool isOwner;
  final void Function(String userId, String label) onKick;
  final Set<String> onlineUserIds;
  final String query;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Large packs (up to 1000) would otherwise build every row + avatar
    // request eagerly. Cap what we render and summarize the rest.
    const maxShown = 50;
    final q = query.trim().toLowerCase();
    final members = q.isEmpty
        ? trip.members
        : trip.members.where((m) => m.label.toLowerCase().contains(q)).toList();
    final total = members.length;
    final shown = total > maxShown ? maxShown : total;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: AppRadii.lg,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < shown; i++) ...[
            InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MemberProfileScreen(
                    tripId: trip.id,
                    userId: members[i].userId,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    _PresenceAvatar(
                      name: members[i].label,
                      avatarUrl: members[i].avatarUrl,
                      online: onlineUserIds.contains(members[i].userId),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            members[i].label,
                            style: textTheme.titleSmall,
                          ),
                          Text(
                            members[i].role.toUpperCase(),
                            style: textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isOwner && members[i].role != 'owner')
                      IconButton(
                        tooltip: 'Remove from trip',
                        icon: const Icon(Icons.person_remove_outlined),
                        color: scheme.error,
                        onPressed: () =>
                            onKick(members[i].userId, members[i].label),
                      ),
                    Icon(
                      Icons.chevron_right,
                      color: scheme.onSurfaceVariant,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            if (i < shown - 1)
              Divider(
                height: 1,
                thickness: 1,
                indent: AppSpacing.lg + AppSpacing.sm,
                color: scheme.surfaceContainerHighest,
              ),
          ],
          if (total > shown) ...[
            Divider(
              height: 1,
              thickness: 1,
              indent: AppSpacing.lg + AppSpacing.sm,
              color: scheme.surfaceContainerHighest,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              ),
              child: Text(
                '+ ${total - shown} more in the pack',
                style: textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _IncomingRequests extends StatelessWidget {
  const _IncomingRequests({required this.tripId, required this.requests});

  final String tripId;
  final List<IncomingRequest> requests;

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
          for (var i = 0; i < requests.length; i++) ...[
            InkWell(
              // Opening the requester's profile is where you accept/decline;
              // name + avatar only here, per the privacy decision.
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MemberProfileScreen(
                    tripId: tripId,
                    userId: requests[i].requesterId,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    UserAvatar(
                      name: requests[i].label,
                      avatarUrl: requests[i].avatarUrl,
                      radius: 18,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(requests[i].label, style: textTheme.titleSmall),
                          Text(
                            'wants to share contacts',
                            style: textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: scheme.primary, size: 20),
                  ],
                ),
              ),
            ),
            if (i < requests.length - 1)
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

/// Avatar with a small green/grey presence dot in the bottom-right corner.
class _PresenceAvatar extends StatelessWidget {
  const _PresenceAvatar({
    required this.name,
    required this.avatarUrl,
    required this.online,
  });

  final String name;
  final String? avatarUrl;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        children: [
          UserAvatar(name: name, avatarUrl: avatarUrl, radius: 18),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: online ? const Color(0xFF2ECC71) : scheme.outline,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.surfaceContainer, width: 2),
              ),
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

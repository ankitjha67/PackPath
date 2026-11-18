import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/widgets/user_avatar.dart';
import '../map/live_trip_controller.dart';
import '../navigation/navigation_repository.dart';
import '../trips/waypoints_repository.dart';
import 'establishment_icons.dart';
import 'establishments_repository.dart';

/// Service tags a member can attach to a rating with one tap.
const _suggestedTags = [
  'quick service',
  'fair price',
  'clean',
  'friendly',
  'good food',
  'reliable',
  'open late',
];

/// Detail + ratings for one establishment. Rate it, read reviews, call,
/// navigate, and add it as a stop on the current trip (reuse across trips).
class EstablishmentSheet extends ConsumerStatefulWidget {
  const EstablishmentSheet({
    super.key,
    required this.establishment,
    this.tripId,
  });

  final EstablishmentDto establishment;
  final String? tripId;

  @override
  ConsumerState<EstablishmentSheet> createState() => _EstablishmentSheetState();
}

class _EstablishmentSheetState extends ConsumerState<EstablishmentSheet> {
  late EstablishmentDto _est = widget.establishment;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final meta = categoryMeta(_est.category);
    final ratingsAsync = ref.watch(establishmentRatingsProvider(_est.id));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_est.avgStars >= 4.5 && _est.ratingCount >= 5)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 4),
                  decoration: BoxDecoration(
                    color: meta.color.withValues(alpha: 0.18),
                    borderRadius: AppRadii.full,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified, size: 14, color: meta.color),
                      const SizedBox(width: 4),
                      Text('PATHFINDER APPROVED',
                          style: textTheme.labelSmall
                              ?.copyWith(color: meta.color, letterSpacing: 1)),
                    ],
                  ),
                ),
              ),
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: meta.color.withValues(alpha: 0.18),
                  child: Icon(meta.icon, color: meta.color),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_est.name,
                          style: textTheme.titleLarge,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      Row(
                        children: [
                          Text(meta.label,
                              style: textTheme.labelMedium
                                  ?.copyWith(color: meta.color)),
                          if (_est.distanceM != null) ...[
                            Text('  ·  ',
                                style: textTheme.labelMedium
                                    ?.copyWith(color: scheme.onSurfaceVariant)),
                            Text(
                              _est.distanceM! >= 1000
                                  ? '${(_est.distanceM! / 1000).toStringAsFixed(1)} km'
                                  : '${_est.distanceM!.round()} m',
                              style: textTheme.labelMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _AggregateStars(avg: _est.avgStars, count: _est.ratingCount),
            if (_est.address != null && _est.address!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(_est.address!,
                    style: textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ),
            const SizedBox(height: AppSpacing.md),
            // Actions
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (_est.phone != null && _est.phone!.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () =>
                        launchUrl(Uri(scheme: 'tel', path: _est.phone)),
                    icon: const Icon(Icons.call, size: 18),
                    label: const Text('Call'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(
                        'https://www.google.com/maps/search/?api=1&query=${_est.lat},${_est.lng}'),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.navigation, size: 18),
                  label: const Text('Navigate'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _rate(5),
                  icon: const Icon(Icons.verified, size: 18),
                  label: const Text('Vouch'),
                ),
                if (widget.tripId != null)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _proposeDetour,
                    icon: const Icon(Icons.alt_route, size: 18),
                    label: const Text('Detour here'),
                  ),
                if (widget.tripId != null)
                  FilledButton.icon(
                    onPressed: _busy ? null : _addToTrip,
                    icon: const Icon(Icons.add_location_alt, size: 18),
                    label: const Text('Add to this trip'),
                  ),
              ],
            ),
            const Divider(height: AppSpacing.lg * 1.5),
            // Your rating
            Text('Your rating', style: textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            _StarPicker(
              value: _est.myStars ?? 0,
              onRate: (stars) => _rate(stars),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : _writeReview,
                icon: const Icon(Icons.rate_review_outlined, size: 18),
                label: Text(
                    _est.myStars == null ? 'Write a review' : 'Edit review'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('Reviews', style: textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Flexible(
              child: ratingsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('Could not load reviews: $e'),
                data: (reviews) {
                  if (reviews.isEmpty) {
                    return Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.md),
                      child: Text('No reviews yet — be the first.',
                          style: textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: reviews.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (_, i) => _ReviewTile(review: reviews[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rate(int stars, {String? comment, String? tags}) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(establishmentsRepositoryProvider.future);
      final updated =
          await repo.rate(_est.id, stars, comment: comment, tags: tags);
      if (!mounted) return;
      setState(() => _est = updated);
      ref.invalidate(establishmentRatingsProvider(_est.id));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Could not rate: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _writeReview() async {
    final result = await showModalBottomSheet<_ReviewDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ReviewComposer(
        initialStars: _est.myStars ?? 0,
      ),
    );
    if (result != null) {
      await _rate(result.stars, comment: result.comment, tags: result.tags);
    }
  }

  /// Propose this place as a pack detour (rest-stop vote), reusing the place's
  /// rating/context. Fans out so every member sees the vote banner.
  Future<void> _proposeDetour() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final repo =
          await ref.read(navigationRepositoryProvider(widget.tripId!).future);
      final dto = await repo.proposeDetour(
        label: _est.name,
        lat: _est.lat,
        lng: _est.lng,
        reason: 'Rest stop (${categoryMeta(_est.category).label})',
        establishmentId: _est.id,
      );
      if (!mounted) return;
      ref.read(liveTripProvider(widget.tripId!).notifier).seedActiveDetour({
        'id': dto.id,
        'label': dto.label,
        'reason': dto.reason,
        'lat': dto.lat,
        'lng': dto.lng,
        'proposer_name': dto.proposerName,
        'proposer_id': dto.proposerId,
        'yes': dto.yes,
        'no': dto.no,
        'my_vote': dto.myVote,
      });
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Proposed "${_est.name}" — pack is voting')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Could not propose: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addToTrip() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final existing =
          await ref.read(tripWaypointsProvider(widget.tripId!).future);
      final repo = await ref.read(waypointsRepositoryProvider.future);
      await repo.add(
        tripId: widget.tripId!,
        name: _est.name,
        lat: _est.lat,
        lng: _est.lng,
        position: existing.length,
      );
      ref.invalidate(tripWaypointsProvider(widget.tripId!));
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${_est.name} added to the trip')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Could not add: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _AggregateStars extends StatelessWidget {
  const _AggregateStars({required this.avg, required this.count});
  final double avg;
  final int count;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (count == 0) {
      return Text('Not rated yet',
          style:
              textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant));
    }
    return Row(
      children: [
        for (int i = 1; i <= 5; i++)
          Icon(
            avg >= i
                ? Icons.star
                : (avg >= i - 0.5 ? Icons.star_half : Icons.star_border),
            size: 20,
            color: const Color(0xFFF59E0B),
          ),
        const SizedBox(width: 6),
        Text(
            '${avg.toStringAsFixed(1)} · $count ${count == 1 ? "rating" : "ratings"}',
            style: textTheme.labelLarge),
      ],
    );
  }
}

class _StarPicker extends StatelessWidget {
  const _StarPicker({required this.value, required this.onRate});
  final int value;
  final ValueChanged<int> onRate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 1; i <= 5; i++)
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => onRate(i),
            icon: Icon(
              i <= value ? Icons.star : Icons.star_border,
              color: const Color(0xFFF59E0B),
              size: 32,
            ),
          ),
      ],
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});
  final EstablishmentRatingDto review;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: AppRadii.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(
                name: review.reviewerName ?? 'Member',
                avatarUrl: review.reviewerAvatar,
                radius: 12,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(review.reviewerName ?? 'Member',
                    style: textTheme.labelLarge),
              ),
              for (int i = 1; i <= 5; i++)
                Icon(i <= review.stars ? Icons.star : Icons.star_border,
                    size: 14, color: const Color(0xFFF59E0B)),
            ],
          ),
          if (review.comment != null && review.comment!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(review.comment!, style: textTheme.bodyMedium),
            ),
          if (review.tagList.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final t in review.tagList)
                    Chip(
                      label: Text(t),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ReviewDraft {
  const _ReviewDraft(this.stars, this.comment, this.tags);
  final int stars;
  final String? comment;
  final String? tags;
}

class _ReviewComposer extends StatefulWidget {
  const _ReviewComposer({required this.initialStars});
  final int initialStars;

  @override
  State<_ReviewComposer> createState() => _ReviewComposerState();
}

class _ReviewComposerState extends State<_ReviewComposer> {
  late int _stars = widget.initialStars == 0 ? 5 : widget.initialStars;
  final _comment = TextEditingController();
  final Set<String> _tags = {};

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.base,
          right: AppSpacing.base,
          top: AppSpacing.base,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.base,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rate this place',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            _StarPicker(
                value: _stars, onRate: (s) => setState(() => _stars = s)),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _comment,
              maxLength: 500,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                hintText: 'What was the service like? (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in _suggestedTags)
                  FilterChip(
                    label: Text(t),
                    selected: _tags.contains(t),
                    onSelected: (on) =>
                        setState(() => on ? _tags.add(t) : _tags.remove(t)),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  _ReviewDraft(
                    _stars,
                    _comment.text.trim().isEmpty ? null : _comment.text.trim(),
                    _tags.isEmpty ? null : _tags.join(','),
                  ),
                ),
                child: const Text('Submit review'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

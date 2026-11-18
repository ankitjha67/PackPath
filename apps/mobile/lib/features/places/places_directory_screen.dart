import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import 'establishment_icons.dart';
import 'establishment_sheet.dart';
import 'establishments_repository.dart';

/// Browsable directory of rated places near the pack. Filter by category, open
/// a place to rate it or add it to the trip — these persist across every trip.
class PlacesDirectoryScreen extends ConsumerStatefulWidget {
  const PlacesDirectoryScreen({
    super.key,
    required this.tripId,
    this.anchor,
  });

  final String tripId;
  final LatLng? anchor;

  @override
  ConsumerState<PlacesDirectoryScreen> createState() =>
      _PlacesDirectoryScreenState();
}

class _PlacesDirectoryScreenState extends ConsumerState<PlacesDirectoryScreen> {
  String? _category; // null = all

  String get _key {
    final a = widget.anchor;
    if (a == null) return '0|0|${_category ?? ''}';
    return '${a.latitude.toStringAsFixed(2)}|${a.longitude.toStringAsFixed(2)}'
        '|${_category ?? ''}';
  }

  @override
  Widget build(BuildContext context) {
    final placesAsync = ref.watch(nearbyEstablishmentsProvider(_key));
    return Scaffold(
      appBar: AppBar(title: const Text('Places')),
      floatingActionButton: widget.anchor == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _addPlace,
              icon: const Icon(Icons.add_location_alt),
              label: const Text('Mark here'),
            ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6, top: 8),
                  child: ChoiceChip(
                    label: const Text('All'),
                    selected: _category == null,
                    onSelected: (_) => setState(() => _category = null),
                  ),
                ),
                for (final c in kCategories)
                  Padding(
                    padding: const EdgeInsets.only(right: 6, top: 8),
                    child: ChoiceChip(
                      avatar: Icon(c.icon, size: 16, color: c.color),
                      label: Text(c.label),
                      selected: _category == c.key,
                      onSelected: (_) => setState(() => _category = c.key),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: placesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load: $e')),
              data: (places) {
                if (places.isEmpty) {
                  return const _PlacesEmpty();
                }
                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(nearbyEstablishmentsProvider(_key)),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: places.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (_, i) => _PlaceRow(
                      place: places[i],
                      onTap: () => _open(places[i]),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _open(EstablishmentDto place) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          EstablishmentSheet(establishment: place, tripId: widget.tripId),
    ).whenComplete(() => ref.invalidate(nearbyEstablishmentsProvider(_key)));
  }

  Future<void> _addPlace() async {
    final anchor = widget.anchor;
    if (anchor == null) return;
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _DirectoryMarkForm(),
    );
    if (result == null || !mounted) return;
    final (name, category) = result;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(establishmentsRepositoryProvider.future);
      await repo.create(
        name: name,
        category: category,
        lat: anchor.latitude,
        lng: anchor.longitude,
      );
      ref.invalidate(nearbyEstablishmentsProvider(_key));
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Marked "$name"')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Could not mark: $e')));
    }
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({required this.place, required this.onTap});
  final EstablishmentDto place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = categoryMeta(place.category);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final approved = place.avgStars >= 4.5 && place.ratingCount >= 5;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.full,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: AppRadii.full,
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: meta.color.withValues(alpha: 0.18),
              child: Icon(meta.icon, color: meta.color),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          place.name,
                          style: textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (approved) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.verified, size: 15, color: scheme.secondary),
                      ],
                    ],
                  ),
                  Row(
                    children: [
                      if (place.ratingCount > 0) ...[
                        const Icon(
                          Icons.star,
                          size: 14,
                          color: Color(0xFFF59E0B),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${place.avgStars.toStringAsFixed(1)} (${place.ratingCount})',
                          style: textTheme.labelMedium,
                        ),
                      ] else
                        Text(
                          'Not rated',
                          style: textTheme.labelMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      Text(
                        '  ·  ${meta.label}',
                        style: textTheme.labelMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (place.distanceM != null)
              Text(
                place.distanceM! >= 1000
                    ? '${(place.distanceM! / 1000).toStringAsFixed(1)} km'
                    : '${place.distanceM!.round()} m',
                style: textTheme.labelMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _PlacesEmpty extends StatelessWidget {
  const _PlacesEmpty();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.place_outlined,
              size: 48,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'No places here yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Long-press the map (or tap "Mark here") to add fuel stops, '
              'dhabas, mechanics and more — then rate them for the next trip.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Minimal name+category form reused by the directory FAB.
class _DirectoryMarkForm extends StatefulWidget {
  const _DirectoryMarkForm();

  @override
  State<_DirectoryMarkForm> createState() => _DirectoryMarkFormState();
}

class _DirectoryMarkFormState extends State<_DirectoryMarkForm> {
  final _name = TextEditingController();
  String _category = 'fuel';

  @override
  void dispose() {
    _name.dispose();
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
            Text('Mark a place', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in kCategories)
                  ChoiceChip(
                    avatar: Icon(
                      c.icon,
                      size: 16,
                      color: _category == c.key ? Colors.white : c.color,
                    ),
                    label: Text(c.label),
                    selected: _category == c.key,
                    selectedColor: c.color,
                    labelStyle: TextStyle(
                      color: _category == c.key ? Colors.white : null,
                    ),
                    onSelected: (_) => setState(() => _category = c.key),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final name = _name.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(context, (name, _category));
                },
                child: const Text('Mark place'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

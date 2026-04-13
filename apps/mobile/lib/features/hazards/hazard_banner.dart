import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/kinetic_path_tokens.dart';
import '../trips/waypoints_repository.dart';
import 'hazard_layer.dart' show HazardLayer;
import 'hazard_model.dart';
import 'hazard_proximity.dart';
import 'hazards_repository.dart';

/// Top-of-screen slide-down banner that alerts when hazards are near
/// the active trip's route.
///
/// Watches `tripHazardsProvider(tripId)` and `tripRouteProvider(tripId)`,
/// runs `hazardsNearRoute(route, hazards)`, and shows a count + a
/// tap-to-expand sheet when the set is non-empty. Dismissible; the
/// dismiss state is keyed on the set of hazard ids so changes in the
/// hazard set re-show the banner automatically.
class HazardBanner extends ConsumerStatefulWidget {
  const HazardBanner({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<HazardBanner> createState() => _HazardBannerState();
}

class _HazardBannerState extends ConsumerState<HazardBanner> {
  /// Set of hazard ids the user has explicitly dismissed. We re-show
  /// the banner if the hazard set grows or changes.
  Set<String> _dismissedIds = const {};

  @override
  Widget build(BuildContext context) {
    final hazardsAsync = ref.watch(tripHazardsProvider(widget.tripId));
    final routeAsync = ref.watch(tripRouteProvider(widget.tripId));

    final hazards = hazardsAsync.maybeWhen(
      data: (h) => h,
      orElse: () => const <HazardDto>[],
    );
    final List<LatLng> route = routeAsync.maybeWhen(
      data: (r) => r?.points ?? const <LatLng>[],
      orElse: () => const <LatLng>[],
    );

    final near = hazardsNearRoute(route, hazards);
    final currentIds = near.map((h) => h.id).toSet();

    // If the hazard set changed since the last dismiss, forget the
    // dismissal — a new hazard is worth re-showing the banner for.
    final isDismissed =
        _dismissedIds.isNotEmpty && _dismissedIds.containsAll(currentIds);

    final visible = near.isNotEmpty && !isDismissed;

    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, -1.5),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 220),
        child: visible
            ? _BannerSurface(
                hazards: near,
                onDismiss: () {
                  setState(() => _dismissedIds = currentIds);
                },
                onExpand: () => _openDetails(context, near),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

void _openDetails(BuildContext context, List<HazardDto> hazards) {
  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _HazardListSheet(hazards: hazards),
  );
}

class _BannerSurface extends StatelessWidget {
  const _BannerSurface({
    required this.hazards,
    required this.onDismiss,
    required this.onExpand,
  });

  final List<HazardDto> hazards;
  final VoidCallback onDismiss;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KineticPathTokens>()!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final count = hazards.length;
    return ClipRRect(
      borderRadius: AppRadii.lg,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: tokens
              .glassmorphismDecoration(borderRadius: AppRadii.lg)
              .copyWith(
                border: Border.all(
                  color: scheme.error.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.error,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: scheme.onError,
                  size: 18,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$count hazard${count == 1 ? '' : 's'} near your route',
                      style: textTheme.titleSmall,
                    ),
                    Text(
                      'Tap to review',
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Review',
                icon: const Icon(Icons.chevron_right),
                onPressed: onExpand,
              ),
              IconButton(
                tooltip: 'Dismiss',
                icon: const Icon(Icons.close),
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HazardListSheet extends StatelessWidget {
  const _HazardListSheet({required this.hazards});

  final List<HazardDto> hazards;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.base,
          0,
          AppSpacing.base,
          AppSpacing.base,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              'Hazards near your route',
              style: textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.base),
            child: Text(
              'Sorted by distance. Tap a row on the map for details.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final hazard in hazards)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _HazardListRow(hazard: hazard),
            ),
        ],
      ),
    );
  }
}

class _HazardListRow extends StatelessWidget {
  const _HazardListRow({required this.hazard});

  final HazardDto hazard;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadii.lg,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(hazard.title, style: textTheme.titleSmall),
                Text(
                  hazard.category.toUpperCase(),
                  style: textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            hazard.severity.toUpperCase(),
            style: textTheme.labelSmall?.copyWith(
              color:
                  hazard.severity == 'severe' ? scheme.error : scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Re-export the HazardLayer symbol so callers that import the banner
/// don't also need to import hazard_layer.dart just to place the map
/// overlay. Tiny convenience but keeps trip_map_screen's import list
/// shorter.
typedef HazardMarkerLayer = HazardLayer;

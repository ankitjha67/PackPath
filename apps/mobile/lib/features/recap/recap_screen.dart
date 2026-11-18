import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/kinetic_path_tokens.dart';
import '../../shared/widgets/user_avatar.dart';
import '../trips/trips_repository.dart';

/// Trip Recap — the `designs/trip_recap_card` summary card: a mission header,
/// a 2×2 big-number stat grid, a per-member breakdown, the hour-of-day
/// heatmap, a pack-members strip and a shareable summary.
class TripRecapScreen extends ConsumerWidget {
  const TripRecapScreen({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recapAsync = ref.watch(_recapProvider(tripId));
    final trip = ref.watch(tripDetailProvider(tripId)).valueOrNull;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<KineticPathTokens>()!;

    return Scaffold(
      appBar: AppBar(title: const Text('Trip recap')),
      body: recapAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load recap: $e')),
        data: (recap) {
          final members = (recap['members'] as List?) ?? const [];
          final heatmap = (recap['hour_heatmap'] as Map?) ?? const {};
          final distance = '${recap['total_distance_km'] ?? 0}';
          final topSpeed = '${recap['top_speed_kmh'] ?? 0}';
          final carbon = '${recap['carbon_kg'] ?? 0}';
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.base),
            children: [
              // Mission header.
              Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: AppRadii.full,
                ),
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'EXPEDITION RECAP',
                            style: textTheme.labelMedium?.copyWith(
                              color: scheme.secondary,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            trip?.name ?? 'Trip',
                            style: textTheme.headlineSmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'LOG ID',
                          style: textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          '#${tripId.substring(0, 4).toUpperCase()}',
                          style: textTheme.titleLarge
                              ?.copyWith(color: scheme.primary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              // 2x2 big-number grid.
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpacing.md,
                crossAxisSpacing: AppSpacing.md,
                childAspectRatio: 1.6,
                children: [
                  _StatTile(
                    label: 'TOTAL DISTANCE',
                    value: distance,
                    unit: 'km',
                  ),
                  _StatTile(
                    label: 'TOP SPEED',
                    value: topSpeed,
                    unit: 'km/h',
                    accent: true,
                  ),
                  _StatTile(label: 'CARBON', value: carbon, unit: 'kg CO₂'),
                  _StatTile(
                    label: 'PACK SIZE',
                    value: '${members.length}',
                    unit: '',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'PER MEMBER',
                style: textTheme.labelMedium?.copyWith(
                  letterSpacing: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final m in members)
                Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: AppRadii.full,
                  ),
                  child: ListTile(
                    leading: UserAvatar(
                      name: (m['display_name'] as String?) ??
                          (m['user_id'] as String).substring(0, 6),
                      avatarUrl: m['avatar_url'] as String?,
                      radius: 18,
                    ),
                    title: Text(
                      (m['display_name'] as String?) ??
                          'Member ${(m['user_id'] as String).substring(0, 6)}',
                    ),
                    subtitle: Text(
                      '${(((m['distance_m'] as num?) ?? 0) / 1000).toStringAsFixed(1)} km · '
                      'top ${(((m['top_speed_mps'] as num?) ?? 0) * 3.6).toStringAsFixed(0)} km/h',
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'HOUR OF DAY (UTC)',
                style: textTheme.labelMedium?.copyWith(
                  letterSpacing: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: AppRadii.full,
                ),
                padding: const EdgeInsets.all(AppSpacing.base),
                child: _HourHeatmap(values: heatmap.cast<dynamic, dynamic>()),
              ),
              const SizedBox(height: AppSpacing.lg),
              // Share CTA.
              Container(
                decoration: BoxDecoration(
                  gradient: tokens.ctaGradient,
                  borderRadius: AppRadii.full,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: AppRadii.full,
                    onTap: () => _share(
                      context,
                      trip?.name ?? 'Trip',
                      distance,
                      topSpeed,
                      members.length,
                    ),
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.base),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.ios_share, color: Colors.white),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            'Share recap',
                            style: textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _share(
    BuildContext context,
    String name,
    String distance,
    String topSpeed,
    int members,
  ) {
    final text = 'PackPath recap — $name\n'
        '$distance km covered · top $topSpeed km/h · $members in the pack.';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Recap copied — paste it anywhere.')),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.unit,
    this.accent = false,
  });
  final String label;
  final String value;
  final String unit;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final color = accent ? scheme.primary : scheme.onSurface;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: accent
            ? scheme.primaryContainer.withValues(alpha: 0.25)
            : scheme.surfaceContainerLow,
        borderRadius: AppRadii.full,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              color: scheme.onSurfaceVariant,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: textTheme.displaySmall?.copyWith(color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _HourHeatmap extends StatelessWidget {
  const _HourHeatmap({required this.values});
  final Map<dynamic, dynamic> values;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxFrames = values.values.isEmpty
        ? 1
        : values.values
            .map((v) => (v as num).toInt())
            .reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: 64,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (int hour = 0; hour < 24; hour++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: ClipRRect(
                  borderRadius: AppRadii.lg,
                  child: Container(
                    height: maxFrames == 0
                        ? 2
                        : (((values[hour] ?? values[hour.toString()]) ?? 0)
                                        as num)
                                    .toDouble() /
                                maxFrames *
                                60 +
                            2,
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

final _recapProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, tripId) async {
  ref.watch(sessionEpochProvider);
  final dio = await ref.watch(apiClientProvider.future);
  final response = await dio.get('/trips/$tripId/recap');
  return response.data as Map<String, dynamic>;
});

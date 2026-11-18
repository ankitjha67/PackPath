import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/kinetic_path_tokens.dart';

/// Personal "Kinetic Profile" — lifetime telemetry from /me/stats, styled after
/// `designs/advanced_analytics_hub` with the metrics PackPath actually tracks:
/// a distance hero plus a grid of lifetime stats.
class PersonalStatsScreen extends ConsumerWidget {
  const PersonalStatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(_statsProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<KineticPathTokens>()!;
    return Scaffold(
      appBar: AppBar(title: const Text('Kinetic profile')),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load stats: $e')),
        data: (stats) {
          final distance = '${stats['total_distance_km'] ?? 0}';
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.base),
            children: [
              Text('LIFETIME TELEMETRY',
                  style: textTheme.labelMedium
                      ?.copyWith(letterSpacing: 2, color: scheme.secondary)),
              const SizedBox(height: AppSpacing.xs),
              // Distance hero.
              Container(
                decoration: BoxDecoration(
                  gradient: tokens.ctaGradient,
                  borderRadius: AppRadii.full,
                ),
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TOTAL DISTANCE COVERED',
                        style: textTheme.labelMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                            letterSpacing: 1.2)),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(distance,
                            style: textTheme.displayMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(width: 6),
                        Text('km',
                            style: textTheme.titleMedium
                                ?.copyWith(color: Colors.white)),
                      ],
                    ),
                    Text(
                        'Longest single trip: ${stats['longest_trip_km'] ?? 0} km',
                        style: textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9))),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpacing.md,
                crossAxisSpacing: AppSpacing.md,
                childAspectRatio: 1.5,
                children: [
                  _StatTile(
                      label: 'TOP SPEED',
                      value: '${stats['top_speed_kmh'] ?? 0}',
                      unit: 'km/h'),
                  _StatTile(
                      label: 'TRIPS OWNED',
                      value: '${stats['trips_owned'] ?? 0}',
                      unit: ''),
                  _StatTile(
                      label: 'TRIPS JOINED',
                      value: '${stats['trips_joined'] ?? 0}',
                      unit: ''),
                  _StatTile(
                      label: 'CARBON',
                      value: '${stats['carbon_kg'] ?? 0}',
                      unit: 'kg'),
                  if (stats['favorite_hour_utc'] != null)
                    _StatTile(
                        label: 'FAV HOUR (UTC)',
                        value: '${stats['favorite_hour_utc']}',
                        unit: ':00'),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(
      {required this.label, required this.value, required this.unit});
  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadii.full,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.2, color: scheme.onSurfaceVariant)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(value,
                    style: textTheme.displaySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(unit,
                    style: textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

final _statsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(sessionEpochProvider);
  final dio = await ref.watch(apiClientProvider.future);
  final response = await dio.get('/me/stats');
  return response.data as Map<String, dynamic>;
});

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import 'waypoints_repository.dart';

/// Icon + colour for a weather condition string (shared by the sheet and the
/// live route-ahead widget).
({IconData icon, Color color}) conditionVisual(String condition) {
  switch (condition.toLowerCase()) {
    case 'rain':
    case 'drizzle':
      return (icon: Icons.umbrella, color: const Color(0xFF3B82F6));
    case 'thunderstorm':
      return (icon: Icons.thunderstorm, color: const Color(0xFF7C3AED));
    case 'snow':
      return (icon: Icons.ac_unit, color: const Color(0xFF60A5FA));
    case 'clouds':
      return (icon: Icons.cloud, color: const Color(0xFF94A3B8));
    case 'clear':
      return (icon: Icons.wb_sunny, color: const Color(0xFFF59E0B));
    default:
      return (icon: Icons.cloud_queue, color: const Color(0xFF94A3B8));
  }
}

/// Weather along the trip's waypoints. Real data when OpenWeather is
/// configured on the server, otherwise a deterministic dev sample.
class TripWeatherSheet extends ConsumerWidget {
  const TripWeatherSheet({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final weatherAsync = ref.watch(tripWeatherProvider(tripId));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_outlined),
                const SizedBox(width: AppSpacing.sm),
                Text('Weather along the route', style: textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.invalidate(tripWeatherProvider(tripId)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Flexible(
              child: weatherAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Could not load: $e')),
                data: (stops) {
                  if (stops.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Text(
                        'Add waypoints to see the forecast along your route.',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: stops.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (_, i) => _WeatherTile(weather: stops[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherTile extends StatelessWidget {
  const _WeatherTile({required this.weather});

  final WaypointWeather weather;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final c = conditionVisual(weather.condition);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: AppRadii.lg,
      ),
      child: Row(
        children: [
          Icon(c.icon, color: c.color, size: 32),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(weather.name, style: textTheme.titleSmall),
                Text(
                  weather.condition,
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${weather.temperatureC.round()}°C',
                style: textTheme.titleMedium,
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.air, size: 13, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 2),
                  Text(
                    '${weather.windKmh.round()} km/h',
                    style: textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.water_drop_outlined,
                      size: 13, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 2),
                  Text(
                    '${(weather.pop * 100).round()}%',
                    style: textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

/// Server-computed trip recap. Shows total distance, top speed, carbon
/// estimate, per-member breakdown, and the hour-of-day heatmap.
class TripRecapScreen extends ConsumerWidget {
  const TripRecapScreen({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recapAsync = ref.watch(_recapProvider(tripId));
    return Scaffold(
      appBar: AppBar(title: const Text('Trip recap')),
      body: recapAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (recap) {
          final members = (recap['members'] as List?) ?? const [];
          final heatmap = (recap['hour_heatmap'] as Map?) ?? const {};
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatCard(
                label: 'Total distance',
                value: '${recap['total_distance_km']} km',
              ),
              _StatCard(
                label: 'Top speed',
                value: '${recap['top_speed_kmh']} km/h',
              ),
              _StatCard(
                label: 'Carbon estimate',
                value: '${recap['carbon_kg']} kg CO₂',
              ),
              const SizedBox(height: 16),
              Text('Per member',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final m in members)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(
                      'Member ${(m['user_id'] as String).substring(0, 6)}'),
                  subtitle: Text(
                    '${(((m['distance_m'] as num?) ?? 0) / 1000).toStringAsFixed(1)} km · '
                    'top ${(((m['top_speed_mps'] as num?) ?? 0) * 3.6).toStringAsFixed(0)} km/h',
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                'Hour of day (UTC)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _HourHeatmap(values: heatmap.cast<dynamic, dynamic>()),
            ],
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            const Spacer(),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}

class _HourHeatmap extends StatelessWidget {
  const _HourHeatmap({required this.values});
  final Map<dynamic, dynamic> values;

  @override
  Widget build(BuildContext context) {
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
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Container(
                  height: maxFrames == 0
                      ? 0
                      : (((values[hour] ?? values[hour.toString()]) ?? 0)
                                  as num)
                              .toDouble() /
                          maxFrames *
                          60,
                  color: Theme.of(context).colorScheme.primary,
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
  final dio = await ref.watch(apiClientProvider.future);
  final response = await dio.get('/trips/$tripId/recap');
  return response.data as Map<String, dynamic>;
});

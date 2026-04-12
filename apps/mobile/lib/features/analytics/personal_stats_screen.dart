import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

/// Personal "wrapped" stats — uses the /me/stats endpoint.
class PersonalStatsScreen extends ConsumerWidget {
  const PersonalStatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(_statsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Your stats')),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (stats) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Tile(
              icon: Icons.straighten,
              label: 'Total distance',
              value: '${stats['total_distance_km']} km',
            ),
            _Tile(
              icon: Icons.timeline,
              label: 'Longest trip',
              value: '${stats['longest_trip_km']} km',
            ),
            _Tile(
              icon: Icons.speed,
              label: 'Top speed',
              value: '${stats['top_speed_kmh']} km/h',
            ),
            _Tile(
              icon: Icons.flag_outlined,
              label: 'Trips owned',
              value: '${stats['trips_owned']}',
            ),
            _Tile(
              icon: Icons.group,
              label: 'Trips joined',
              value: '${stats['trips_joined']}',
            ),
            _Tile(
              icon: Icons.eco,
              label: 'Carbon footprint',
              value: '${stats['carbon_kg']} kg CO₂',
            ),
            if (stats['favorite_hour_utc'] != null)
              _Tile(
                icon: Icons.access_time,
                label: 'Favourite drive hour (UTC)',
                value: '${stats['favorite_hour_utc']}:00',
              ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: Text(
          value,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    );
  }
}

final _statsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final dio = await ref.watch(apiClientProvider.future);
  final response = await dio.get('/me/stats');
  return response.data as Map<String, dynamic>;
});

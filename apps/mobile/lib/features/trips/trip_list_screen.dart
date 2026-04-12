import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'trips_repository.dart';

class TripListScreen extends ConsumerWidget {
  const TripListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(myTripsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your trips'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Join trip',
            onPressed: () => context.push('/trips/join'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New trip'),
        onPressed: () => context.push('/trips/new'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myTripsProvider),
        child: tripsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text('Failed to load trips:\n$err'),
              ),
            ],
          ),
          data: (trips) {
            if (trips.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No trips yet.\nCreate one or join with a code.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              itemCount: trips.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final t = trips[i];
                return ListTile(
                  leading: const Icon(Icons.map_outlined),
                  title: Text(t.name),
                  subtitle: Text(
                    '${t.status.toUpperCase()} · '
                    '${t.members.length} member${t.members.length == 1 ? '' : 's'} · '
                    'code ${t.joinCode}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/trips/${t.id}'),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

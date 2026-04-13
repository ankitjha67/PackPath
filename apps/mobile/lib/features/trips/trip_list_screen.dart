import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/trip.dart';
import 'trips_repository.dart';

class TripListScreen extends ConsumerWidget {
  const TripListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(myTripsProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Your trips'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Active'),
              Tab(text: 'Past'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: 'Join trip',
              onPressed: () => context.push('/trips/join'),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Settings',
              onPressed: () => context.push('/settings'),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text('New trip'),
          onPressed: () => context.push('/trips/new'),
        ),
        body: tripsAsync.when(
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
            final active = trips
                .where((t) => t.status != 'ended' && t.status != 'cancelled')
                .toList();
            final past = trips
                .where((t) => t.status == 'ended' || t.status == 'cancelled')
                .toList();
            return TabBarView(
              children: [
                _TripListTab(
                  trips: active,
                  emptyMessage:
                      'No active trips.\nCreate one or join with a code.',
                  onRefresh: () async => ref.invalidate(myTripsProvider),
                ),
                _TripListTab(
                  trips: past,
                  emptyMessage: 'Past trips appear here once they end.\n'
                      'Recap and history will land in polish week.',
                  onRefresh: () async => ref.invalidate(myTripsProvider),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TripListTab extends StatelessWidget {
  const _TripListTab({
    required this.trips,
    required this.emptyMessage,
    required this.onRefresh,
  });

  final List<TripDto> trips;
  final String emptyMessage;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: trips.isEmpty
          ? ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(emptyMessage, textAlign: TextAlign.center),
                ),
              ],
            )
          : ListView.separated(
              itemCount: trips.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final t = trips[i];
                return ListTile(
                  leading: Icon(
                    t.status == 'ended' ? Icons.history : Icons.map_outlined,
                  ),
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
            ),
    );
  }
}

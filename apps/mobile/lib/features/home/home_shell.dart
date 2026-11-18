import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../shared/models/trip.dart';
import '../chat/chat_screen.dart';
import '../profile/profile_screen.dart';
import '../trips/trip_list_screen.dart';
import '../trips/trip_map_screen.dart';
import '../trips/trips_repository.dart';

/// The persistent bottom-nav shell from the designs folder: Lobby / Radar /
/// Chat / Profile. The Radar tab embeds the full live map; detail flows still
/// push full-screen over the shell.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          TripListScreen(),
          _RadarTab(),
          _ChatTab(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Lobby',
          ),
          NavigationDestination(
            icon: Icon(Icons.radar_outlined),
            selectedIcon: Icon(Icons.radar),
            label: 'Radar',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

/// Resolves the current active trip (first non-ended) for the Radar / Chat tabs.
TripDto? _activeTrip(WidgetRef ref) {
  final trips = ref.watch(myTripsProvider).valueOrNull ?? const <TripDto>[];
  for (final t in trips) {
    if (t.status != 'ended' && t.status != 'cancelled') return t;
  }
  return null;
}

class _RadarTab extends ConsumerWidget {
  const _RadarTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = _activeTrip(ref);
    if (trip == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Radar')),
        body: const _TabEmpty(
          icon: Icons.radar,
          title: 'No active pack',
          body: 'Create or join a pack to open the live radar HUD.',
        ),
      );
    }
    // Embed the full live map (weather pill, nav HUD, FABs and menu) directly in
    // the Radar tab. As a tab root it shows no back button, and its bottom
    // overlays sit above the shell's nav bar automatically.
    return TripMapScreen(key: ValueKey(trip.id), tripId: trip.id);
  }
}

class _ChatTab extends ConsumerWidget {
  const _ChatTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = _activeTrip(ref);
    if (trip == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: const _TabEmpty(
          icon: Icons.chat_bubble_outline,
          title: 'No active pack',
          body: 'Join or create a pack to chat with your trail partners.',
        ),
      );
    }
    return ChatScreen(tripId: trip.id);
  }
}

class _TabEmpty extends StatelessWidget {
  const _TabEmpty({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: scheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.sm),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              body,
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

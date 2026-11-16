import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/kinetic_path_tokens.dart';
import '../../shared/models/trip.dart';
import '../chat/chat_screen.dart';
import '../profile/profile_screen.dart';
import '../trips/trip_list_screen.dart';
import '../trips/trips_repository.dart';

/// The persistent bottom-nav shell from the designs folder: Lobby / Radar /
/// Chat / Profile. The immersive map, chat detail and other flows still push
/// full-screen over this shell; the nav bar lives on the four hub tabs.
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
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<KineticPathTokens>()!;
    final trip = _activeTrip(ref);
    return Scaffold(
      appBar: AppBar(title: const Text('Radar')),
      body: trip == null
          ? const _TabEmpty(
              icon: Icons.radar,
              title: 'No active pack',
              body: 'Create or join a pack to open the live radar HUD.',
            )
          : Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('ACTIVE MISSION',
                      style: textTheme.labelMedium?.copyWith(
                          letterSpacing: 1.5, color: scheme.secondary)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(trip.name, style: textTheme.headlineMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${trip.members.length} '
                    'member${trip.members.length == 1 ? '' : 's'} · '
                    'code ${trip.joinCode}',
                    style: textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: AppRadii.full,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.map_outlined,
                                size: 64, color: scheme.onSurfaceVariant),
                            const SizedBox(height: AppSpacing.sm),
                            Text('Live group map',
                                style: textTheme.titleMedium),
                            Text('breadcrumbs · pace · hazards · formation',
                                style: textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.base),
                  Container(
                    decoration: BoxDecoration(
                      gradient: tokens.ctaGradient,
                      borderRadius: AppRadii.full,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: AppRadii.full,
                        onTap: () => context.push('/trips/${trip.id}'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.base),
                          child: Center(
                            child: Text('ENTER HUD',
                                style: textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.5)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
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
  const _TabEmpty(
      {required this.icon, required this.title, required this.body});
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
            Text(body,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

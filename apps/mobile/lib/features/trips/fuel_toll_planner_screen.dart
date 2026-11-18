import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/kinetic_path_tokens.dart';
import '../preferences/preferences_repository.dart';
import 'waypoints_repository.dart';

/// Fuel & Toll Planner — the `designs/fuel_toll_planner` flow. Estimates the
/// route's fuel and toll cost for the configured vehicle via the backend cost
/// proxy, with a clear fuel/toll/total breakdown and per-head split.
class FuelTollPlannerScreen extends ConsumerStatefulWidget {
  const FuelTollPlannerScreen({
    super.key,
    required this.tripId,
    required this.memberCount,
  });
  final String tripId;
  final int memberCount;

  @override
  ConsumerState<FuelTollPlannerScreen> createState() =>
      _FuelTollPlannerScreenState();
}

class _FuelTollPlannerScreenState extends ConsumerState<FuelTollPlannerScreen> {
  RouteCost? _cost;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _estimate();
  }

  Future<void> _estimate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final waypoints =
          await ref.read(tripWaypointsProvider(widget.tripId).future);
      if (waypoints.length < 2) {
        setState(() {
          _loading = false;
          _error = 'Add at least two waypoints to plan fuel + tolls.';
        });
        return;
      }
      final prefs = effectivePreferences(ref);
      final repo = await ref.read(waypointsRepositoryProvider.future);
      final cost = await repo.routeCost(
        tripId: widget.tripId,
        coordinates: waypoints.map((w) => w.latLng).toList(),
        vehicle: prefs.vehicleType,
      );
      if (!mounted) return;
      setState(() {
        _cost = cost;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<KineticPathTokens>()!;
    final prefs = effectivePreferences(ref);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fuel & tolls'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _estimate,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  children: [
                    Text(
                      'ROUTE ESTIMATE',
                      style: textTheme.labelMedium?.copyWith(
                        letterSpacing: 2,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    // Hero total.
                    Container(
                      decoration: BoxDecoration(
                        gradient: tokens.ctaGradient,
                        borderRadius: AppRadii.full,
                      ),
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TOTAL FOR THE PACK',
                            style: textTheme.labelMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                              letterSpacing: 1.2,
                            ),
                          ),
                          Text(
                            _money(_cost?.totalCents ?? 0, prefs),
                            style: textTheme.displaySmall
                                ?.copyWith(color: Colors.white),
                          ),
                          Text(
                            '${_cost?.fuelLitres.toStringAsFixed(1) ?? '0'} L fuel · '
                            '${prefs.vehicleType}',
                            style: textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.base),
                    _row(
                      context,
                      Icons.local_gas_station,
                      'Fuel',
                      _money(_cost?.fuelCents ?? 0, prefs),
                    ),
                    _row(
                      context,
                      Icons.toll,
                      'Tolls',
                      _money(_cost?.tollCents ?? 0, prefs),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: AppRadii.full,
                      ),
                      padding: const EdgeInsets.all(AppSpacing.base),
                      child: Row(
                        children: [
                          Icon(
                            Icons.groups,
                            color: scheme.onSecondaryContainer,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Text(
                              'Split ${widget.memberCount} ways',
                              style: textTheme.titleMedium?.copyWith(
                                color: scheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                          Text(
                            _money(
                              widget.memberCount <= 0
                                  ? (_cost?.totalCents ?? 0)
                                  : (_cost?.totalCents ?? 0) ~/
                                      widget.memberCount,
                              prefs,
                            ),
                            style: textTheme.titleLarge
                                ?.copyWith(color: scheme.onSecondaryContainer),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Estimate for the configured vehicle and region. '
                      'Change your vehicle + mileage in Preferences for a '
                      'sharper figure.',
                      style: textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadii.full,
      ),
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Row(
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(label, style: textTheme.titleMedium)),
          Text(value, style: textTheme.titleLarge),
        ],
      ),
    );
  }

  String _money(int cents, PreferencesDto prefs) {
    final symbol = (_cost?.currency ?? 'INR') == 'INR' ? '₹' : '\$';
    return '$symbol${(cents / 100).toStringAsFixed(0)}';
  }
}

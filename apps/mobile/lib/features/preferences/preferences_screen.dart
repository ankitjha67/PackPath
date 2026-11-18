import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../map/map_providers.dart';
import 'preferences_repository.dart';

/// Phase 8 — personalization settings. Units, temperature scale, default map
/// style, and vehicle profile, all synced server-side so they follow the user
/// across devices. Changing the map style also updates the local map picker.
class PreferencesScreen extends ConsumerStatefulWidget {
  const PreferencesScreen({super.key});

  @override
  ConsumerState<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends ConsumerState<PreferencesScreen> {
  PreferencesDto? _prefs;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(preferencesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Preferences')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 40),
                const SizedBox(height: AppSpacing.sm),
                Text('Could not load preferences: $e',
                    textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(preferencesProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (loaded) {
          final p = _prefs ??= loaded;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.base),
            children: [
              const _SectionLabel('UNITS'),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'metric', label: Text('Metric (km)')),
                  ButtonSegment(
                      value: 'imperial', label: Text('Imperial (mi)')),
                ],
                selected: {p.units},
                onSelectionChanged: (s) => _patch(
                    {'units': s.first}, (x) => x.copyWith(units: s.first)),
              ),
              const SizedBox(height: AppSpacing.md),
              const _SectionLabel('TEMPERATURE'),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'c', label: Text('Celsius')),
                  ButtonSegment(value: 'f', label: Text('Fahrenheit')),
                ],
                selected: {p.tempUnit},
                onSelectionChanged: (s) => _patch({'temp_unit': s.first},
                    (x) => x.copyWith(tempUnit: s.first)),
              ),
              const SizedBox(height: AppSpacing.md),
              const _SectionLabel('DEFAULT MAP STYLE'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final mp in MapProvider.values)
                    ChoiceChip(
                      label: Text(mp.displayName),
                      selected: p.mapStyle == mp.id,
                      onSelected: (_) {
                        _patch({'map_style': mp.id},
                            (x) => x.copyWith(mapStyle: mp.id));
                        // Apply to the live map picker immediately too.
                        ref
                            .read(mapProviderControllerProvider.notifier)
                            .set(mp);
                      },
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              const _SectionLabel('MY VEHICLE'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final v in kVehicleTypes)
                    ChoiceChip(
                      label: Text(_vehicleLabel(v)),
                      selected: p.vehicleType == v,
                      onSelected: (_) => _patch({'vehicle_type': v},
                          (x) => x.copyWith(vehicleType: v)),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              _MileageField(
                value: p.mileageKmpl,
                onChanged: (v) => _patch(
                    {'mileage_kmpl': v}, (x) => x.copyWith(mileageKmpl: v)),
              ),
              const SizedBox(height: AppSpacing.md),
              const _SectionLabel('PRIVACY'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Share my location by default'),
                subtitle: const Text(
                    'When you join a trip, start sharing automatically'),
                value: p.shareLocationDefault,
                onChanged: (v) => _patch({'share_location_default': v},
                    (x) => x.copyWith(shareLocationDefault: v)),
              ),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.md),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _patch(
    Map<String, dynamic> patch,
    PreferencesDto Function(PreferencesDto) optimistic,
  ) async {
    final current = _prefs;
    if (current == null || _saving) return;
    setState(() {
      _prefs = optimistic(current);
      _saving = true;
    });
    try {
      final repo = await ref.read(preferencesRepositoryProvider.future);
      final updated = await repo.update(patch);
      if (!mounted) return;
      setState(() => _prefs = updated);
      ref.invalidate(preferencesProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _prefs = current); // roll back
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

String _vehicleLabel(String v) =>
    v.isEmpty ? v : v[0].toUpperCase() + v.substring(1);

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _MileageField extends StatefulWidget {
  const _MileageField({required this.value, required this.onChanged});
  final double? value;
  final ValueChanged<double> onChanged;

  @override
  State<_MileageField> createState() => _MileageFieldState();
}

class _MileageFieldState extends State<_MileageField> {
  late final TextEditingController _c =
      TextEditingController(text: widget.value?.toStringAsFixed(1) ?? '');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        labelText: 'Mileage (km / litre)',
        hintText: 'e.g. 18.5 — sharpens fuel cost estimates',
        border: OutlineInputBorder(),
      ),
      onSubmitted: (raw) {
        final v = double.tryParse(raw.trim());
        if (v != null && v >= 1 && v <= 100) widget.onChanged(v);
      },
    );
  }
}

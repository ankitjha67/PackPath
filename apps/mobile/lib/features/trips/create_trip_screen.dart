import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/kinetic_path_tokens.dart';
import 'trips_repository.dart';

class CreateTripScreen extends ConsumerStatefulWidget {
  const CreateTripScreen({super.key});

  @override
  ConsumerState<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends ConsumerState<CreateTripScreen> {
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = await ref.read(tripsRepositoryProvider.future);
      final trip = await repo.create(name: name);
      ref.invalidate(myTripsProvider);
      if (!mounted) return;
      // Reset the stack to the trips list, then push the new trip's map so the
      // map has a back entry (system Back returns to the list, not out of the
      // app). A bare go('/trips/:id') would replace the whole stack.
      context.go('/trips');
      context.push('/trips/${trip.id}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not create trip: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<KineticPathTokens>()!;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('NEW EXPEDITION',
                  style: textTheme.labelMedium
                      ?.copyWith(letterSpacing: 2, color: scheme.secondary)),
              const SizedBox(height: AppSpacing.xs),
              Text('Name your\nexpedition',
                  style: textTheme.displaySmall
                      ?.copyWith(fontWeight: FontWeight.w700, height: 1.05)),
              const SizedBox(height: AppSpacing.sm),
              Text(
                  'Give the pack a call sign. You can invite members with a '
                  'code right after.',
                  style: textTheme.bodyLarge
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: AppSpacing.xl),
              Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: AppRadii.full,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                child: TextField(
                  controller: _name,
                  autofocus: true,
                  style: textTheme.titleMedium,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Goa road trip',
                    border: InputBorder.none,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: TextStyle(color: scheme.error)),
              ],
              const SizedBox(height: AppSpacing.lg),
              Opacity(
                opacity: _busy ? 0.8 : 1,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: tokens.ctaGradient,
                    borderRadius: AppRadii.full,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: AppRadii.full,
                      onTap: _busy ? null : _create,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.base),
                        child: Center(
                          child: _busy
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('INITIALIZE MISSION',
                                        style: textTheme.titleMedium?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 1)),
                                    const SizedBox(width: AppSpacing.sm),
                                    const Icon(Icons.arrow_forward,
                                        color: Colors.white, size: 18),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

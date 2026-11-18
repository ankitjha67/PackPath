import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/kinetic_path_tokens.dart';
import 'trips_repository.dart';

class JoinTripScreen extends ConsumerStatefulWidget {
  const JoinTripScreen({super.key});

  @override
  ConsumerState<JoinTripScreen> createState() => _JoinTripScreenState();
}

class _JoinTripScreenState extends ConsumerState<JoinTripScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _join() async {
    final code = _code.text.trim().toUpperCase();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-character code');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = await ref.read(tripsRepositoryProvider.future);
      final trip = await repo.joinByCode(code);
      ref.invalidate(myTripsProvider);
      if (!mounted) return;
      // Reset the stack to the trips list, then push the joined trip's map so
      // the map has a back entry (system Back returns to the list, not out of
      // the app). A bare go('/trips/:id') would replace the whole stack.
      context.go('/trips');
      context.push('/trips/${trip.id}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not join: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _code.dispose();
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
              Text('JOIN A PACK',
                  style: textTheme.labelMedium
                      ?.copyWith(letterSpacing: 2, color: scheme.secondary)),
              const SizedBox(height: AppSpacing.xs),
              Text('Enter the\nPack ID',
                  style: textTheme.displaySmall
                      ?.copyWith(fontWeight: FontWeight.w700, height: 1.05)),
              const SizedBox(height: AppSpacing.sm),
              Text(
                  'Ask your marshall for the 6-character code, or scan their '
                  'QR from the invite screen.',
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
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: textTheme.displaySmall?.copyWith(letterSpacing: 8),
                  decoration: const InputDecoration(
                    counterText: '',
                    hintText: 'A B C 1 2 3',
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
                      onTap: _busy ? null : _join,
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
                              : Text('JOIN THE PACK',
                                  style: textTheme.titleMedium?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1)),
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

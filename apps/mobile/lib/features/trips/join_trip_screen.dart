import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
      context.go('/trips/${trip.id}');
    } catch (e) {
      setState(() => _error = 'Could not join: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join a trip')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                decoration: const InputDecoration(
                  labelText: 'Join code',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton(
                onPressed: _busy ? null : _join,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Join'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

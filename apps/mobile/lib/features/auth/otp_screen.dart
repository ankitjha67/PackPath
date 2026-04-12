import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../push/push_service.dart';
import '../trips/trips_repository.dart';
import 'auth_repository.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.phone, this.debugOtp});

  final String phone;
  final String? debugOtp;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  late final TextEditingController _controller;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.debugOtp ?? '');
  }

  Future<void> _registerPush() async {
    try {
      final svc = await ref.read(pushServiceProvider.future);
      await svc.initAndRegister();
    } catch (_) {
      // Push isn't critical for v1; failures stay silent.
    }
  }

  Future<void> _verify() async {
    final code = _controller.text.trim();
    if (code.length < 4) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = await ref.read(authRepositoryProvider.future);
      await repo.verifyOtp(phone: widget.phone, code: code);
      // Bust the trip list cache so the new session sees fresh data.
      ref.invalidate(myTripsProvider);
      // Register for push now that we have a valid bearer token. We
      // don't await — push registration shouldn't block navigation.
      unawaited(_registerPush());
      if (!mounted) return;
      context.go('/trips');
    } catch (e) {
      setState(() => _error = 'Invalid code: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Enter the code sent to ${widget.phone}'),
              if (widget.debugOtp != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Dev mode: ${widget.debugOtp}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 12),
                decoration: const InputDecoration(border: OutlineInputBorder()),
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
                onPressed: _busy ? null : _verify,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Verify and continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

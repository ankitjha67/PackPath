import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _sendOtp() async {
    final phone = _controller.text.trim();
    if (phone.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = await ref.read(authRepositoryProvider.future);
      final result = await repo.requestOtp(phone);
      if (!mounted) return;
      // Forward debug OTP through the URL when the backend is in dev mode so
      // you can verify end-to-end without an SMS gateway.
      final extra = result.debugOtp != null ? '&debug=${result.debugOtp}' : '';
      context.go('/otp?phone=${Uri.encodeComponent(phone)}$extra');
    } catch (e) {
      setState(() => _error = 'Could not send code: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'PackPath',
                style: TextStyle(fontSize: 36, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Find your pack. Move together.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  hintText: '+91 98xxxxxxxx',
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
                onPressed: _busy ? null : _sendOtp,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send OTP'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/kinetic_path_tokens.dart';
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
      if (!mounted) return;
      setState(() => _error = 'Invalid code: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
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
              Row(
                children: [
                  Icon(Icons.verified_user, size: 16, color: scheme.secondary),
                  const SizedBox(width: 4),
                  Text(
                    'AWAITING VERIFICATION',
                    style: textTheme.labelMedium?.copyWith(
                      color: scheme.secondary,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Enter Access Code',
                style: textTheme.displaySmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Verification signal sent to ${widget.phone}',
                style: textTheme.bodyLarge
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (widget.debugOtp != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Dev mode: ${widget.debugOtp}',
                  style: textTheme.bodySmall?.copyWith(color: scheme.tertiary),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: AppRadii.full,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: textTheme.displaySmall?.copyWith(letterSpacing: 10),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    counterText: '',
                    hintText: '— — — —',
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
                      onTap: _busy ? null : _verify,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.base,
                        ),
                        child: Center(
                          child: _busy
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'VERIFY & DEPLOY',
                                  style: textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1,
                                  ),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/kinetic_path_tokens.dart';
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
      if (!mounted) return;
      setState(() => _error = 'Could not send code: $e');
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  ClipRRect(
                    borderRadius: AppRadii.xl,
                    child: Image.asset(
                      'assets/icon/icon.png',
                      width: 32,
                      height: 32,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'PACKPATH',
                    style: textTheme.titleMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.verified_user, size: 16, color: scheme.secondary),
                  const SizedBox(width: 4),
                  Text(
                    'ENCRYPTED',
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.secondary,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Secure\nAuthentication',
                style: textTheme.displaySmall
                    ?.copyWith(fontWeight: FontWeight.w700, height: 1.05),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Initialize deployment by verifying your mobile frequency.',
                style: textTheme.bodyLarge
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.xl),
              Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: AppRadii.full,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Icon(Icons.smartphone, color: scheme.onSurfaceVariant),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        keyboardType: TextInputType.phone,
                        style: textTheme.titleMedium,
                        decoration: const InputDecoration(
                          hintText: '+91 98xxxxxxxx',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    Text(
                      'COMMS-INT',
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: TextStyle(color: scheme.error)),
              ],
              const SizedBox(height: AppSpacing.lg),
              _GradientButton(
                busy: _busy,
                label: 'REQUEST TACTICAL KEY',
                gradient: tokens.ctaGradient,
                onPressed: _busy ? null : _sendOtp,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'By proceeding you agree to the PackPath field operations '
                'manual and privacy protocols.',
                textAlign: TextAlign.center,
                style: textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.busy,
    required this.label,
    required this.gradient,
    required this.onPressed,
  });
  final bool busy;
  final String label;
  final Gradient gradient;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null && !busy ? 0.6 : 1,
      child: Container(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: AppRadii.full,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: AppRadii.full,
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
              child: Center(
                child: busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            label,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          const Icon(
                            Icons.arrow_forward,
                            color: Colors.white,
                            size: 18,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

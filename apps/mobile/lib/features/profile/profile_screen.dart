import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../auth/auth_repository.dart';
import 'me_repository.dart';

/// View + edit the current user's profile.
///
/// Backed by `meProvider` (GET /me) and `MeRepository.update` (PATCH /me).
/// Only `display_name` and `avatar_url` are editable — the backend
/// UserOut schema does not expose email or created_at, so those rows
/// are intentionally absent (flagged as a backend gap in the PR body).
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _displayNameController = TextEditingController();
  MeDto? _lastLoaded;
  bool _dirty = false;
  bool _saving = false;

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    final original = _lastLoaded?.displayName ?? '';
    final current = _displayNameController.text.trim();
    final dirty = current != original;
    if (dirty != _dirty) {
      setState(() => _dirty = dirty);
    }
  }

  Future<void> _save() async {
    if (!_dirty || _saving) return;
    setState(() => _saving = true);
    try {
      final repo = await ref.read(meRepositoryProvider.future);
      final updated = await repo.update(
        displayName: _displayNameController.text.trim(),
      );
      if (!mounted) return;
      ref.invalidate(meProvider);
      setState(() {
        _lastLoaded = updated;
        _dirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save profile: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You will need to request a new OTP to sign back in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.onError,
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final repo = await ref.read(authRepositoryProvider.future);
      await repo.logout();
      if (!mounted) return;
      context.go('/login');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not sign out: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final meAsync = ref.watch(meProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          if (_dirty)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: TextButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ),
        ],
      ),
      body: meAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(meProvider),
        ),
        data: (me) {
          // First-time load: seed the controller + listener.
          if (_lastLoaded?.id != me.id) {
            _lastLoaded = me;
            _displayNameController.removeListener(_onInputChanged);
            _displayNameController.text = me.displayName ?? '';
            _displayNameController.addListener(_onInputChanged);
            _dirty = false;
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.base),
            children: [
              Center(
                child: _AvatarPlaceholder(scheme: scheme),
              ),
              const SizedBox(height: AppSpacing.lg),
              const _FieldLabel(text: 'DISPLAY NAME'),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _displayNameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Your name in the pack',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              const _FieldLabel(text: 'PHONE'),
              const SizedBox(height: AppSpacing.xs),
              _ReadOnlyField(
                value: me.phone,
                leading: Icons.phone_outlined,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Your phone is used to sign in. Contact privacy@packpath.app '
                'to change it.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  foregroundColor: scheme.onError,
                  backgroundColor: scheme.error,
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.md,
                  ),
                ),
                onPressed: _signOut,
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.primary, width: 3),
      ),
      child: Icon(
        Icons.person,
        size: 56,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.primary,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.value, required this.leading});
  final String value;
  final IconData leading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadii.lg,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Icon(leading, color: scheme.onSurfaceVariant, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value,
              style: textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: scheme.error,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Could not load your profile',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

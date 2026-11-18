import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/widgets/user_avatar.dart';
import '../achievements/achievements_screen.dart';
import '../auth/auth_repository.dart';
import '../notifications/notification_settings_screen.dart';
import '../preferences/preferences_screen.dart';
import '../safety/emergency_contacts_screen.dart';
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
  final _bioController = TextEditingController();
  final _countryController = TextEditingController();
  MeDto? _lastLoaded;
  bool _dirty = false;
  bool _saving = false;

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    final me = _lastLoaded;
    final dirty =
        _displayNameController.text.trim() != (me?.displayName ?? '') ||
            _bioController.text.trim() != (me?.bio ?? '') ||
            _countryController.text.trim() != (me?.country ?? '');
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
        bio: _bioController.text.trim(),
        country: _countryController.text.trim(),
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

  /// Re-roll a fresh random avatar. Avatars are deterministic per seed, so a
  /// new random seed yields a new look; persisted via PATCH /me.
  Future<void> _shuffleAvatar() async {
    if (_saving) return;
    setState(() => _saving = true);
    final seed = 'pp${Random().nextInt(1 << 32)}';
    final url = 'https://api.dicebear.com/9.x/bottts/png?seed=$seed';
    try {
      final repo = await ref.read(meRepositoryProvider.future);
      final updated = await repo.update(avatarUrl: url);
      if (!mounted) return;
      ref.invalidate(meProvider);
      setState(() => _lastLoaded = updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not change avatar: $e')),
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
            for (final c in [
              _displayNameController,
              _bioController,
              _countryController,
            ]) {
              c.removeListener(_onInputChanged);
            }
            _displayNameController.text = me.displayName ?? '';
            _bioController.text = me.bio ?? '';
            _countryController.text = me.country ?? '';
            for (final c in [
              _displayNameController,
              _bioController,
              _countryController,
            ]) {
              c.addListener(_onInputChanged);
            }
            _dirty = false;
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.base),
            children: [
              Center(
                child: Column(
                  children: [
                    UserAvatar(
                      name: me.displayName ?? me.phone,
                      avatarUrl: me.avatarUrl,
                      radius: 48,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextButton.icon(
                      onPressed: _saving ? null : _shuffleAvatar,
                      icon: const Icon(Icons.casino_outlined, size: 18),
                      label: const Text('Shuffle avatar'),
                    ),
                  ],
                ),
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
              const _FieldLabel(text: 'BIO'),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _bioController,
                maxLines: 3,
                maxLength: 300,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'A short line about you',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              const _FieldLabel(text: 'COUNTRY'),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _countryController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'e.g. India',
                  prefixIcon: Icon(Icons.public, size: 18),
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
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading:
                      Icon(Icons.notifications_outlined, color: scheme.primary),
                  title: const Text('Notifications'),
                  subtitle: const Text('Categories, quiet hours'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const NotificationSettingsScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: Icon(Icons.tune, color: scheme.primary),
                  title: const Text('Preferences'),
                  subtitle: const Text('Units, map style, vehicle, privacy'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const PreferencesScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading:
                      Icon(Icons.emoji_events_outlined, color: scheme.primary),
                  title: const Text('Achievements'),
                  subtitle: const Text('Badges you have earned on your trips'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AchievementsScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading:
                      Icon(Icons.contact_phone_outlined, color: scheme.error),
                  title: const Text('Emergency contacts'),
                  subtitle: const Text(
                    'People to text if you hit SOS, with your location',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const EmergencyContactsScreen(),
                    ),
                  ),
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

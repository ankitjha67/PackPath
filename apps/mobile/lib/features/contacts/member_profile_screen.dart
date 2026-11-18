import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/widgets/user_avatar.dart';
import '../chat/chat_repository.dart';
import '../map/live_trip_controller.dart';
import 'contacts_repository.dart';

/// View another trip member's public profile and manage the per-trip
/// phone-number connection with them.
class MemberProfileScreen extends ConsumerStatefulWidget {
  const MemberProfileScreen({
    super.key,
    required this.tripId,
    required this.userId,
  });

  final String tripId;
  final String userId;

  @override
  ConsumerState<MemberProfileScreen> createState() =>
      _MemberProfileScreenState();
}

class _MemberProfileScreenState extends ConsumerState<MemberProfileScreen> {
  MemberProfile? _profile;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo =
          await ref.read(contactsRepositoryProvider(widget.tripId).future);
      final p = await repo.profile(widget.userId);
      if (!mounted) return;
      setState(() => _profile = p);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(
    Future<MemberProfile> Function(ContactsRepository) op,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final repo =
          await ref.read(contactsRepositoryProvider(widget.tripId).future);
      final p = await op(repo);
      if (!mounted) return;
      setState(() => _profile = p);
      ref.invalidate(incomingRequestsProvider(widget.tripId));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _nudge() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      await repo.sendNudge(widget.tripId, widget.userId);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Nudge sent')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not send nudge: $e')),
      );
    }
  }

  /// Live online/offline chip driven by WS presence for this trip.
  Widget _presenceChip(BuildContext context) {
    final online = ref
        .watch(liveTripProvider(widget.tripId))
        .onlineUserIds
        .contains(widget.userId);
    final color = online
        ? const Color(0xFF2ECC71)
        : Theme.of(context).colorScheme.outline;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          online ? 'Online now' : 'Offline',
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final p = _profile;

    return Scaffold(
      appBar: AppBar(title: const Text('Member')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : p == null
              ? Center(child: Text(_error ?? 'Could not load profile'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Center(
                      child: UserAvatar(
                        name: p.label,
                        avatarUrl: p.avatarUrl,
                        radius: 48,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(p.label, style: textTheme.headlineSmall),
                    ),
                    const SizedBox(height: 4),
                    Center(child: _presenceChip(context)),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _nudge,
                      icon: const Icon(Icons.bolt, color: Color(0xFF7C3AED)),
                      label: const Text('Nudge to catch up'),
                    ),
                    if (p.country != null && p.country!.isNotEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.public,
                                size: 16,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                p.country!,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (p.bio != null && p.bio!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(p.bio!, style: textTheme.bodyMedium),
                      ),
                    ],
                    const SizedBox(height: 24),
                    _ConnectionSection(
                      profile: p,
                      busy: _busy,
                      onRequest: () => _run((r) => r.request(p.id)),
                      onAccept: () => _run((r) => r.accept(p.requestId!)),
                      onDecline: () async {
                        if (_busy) return;
                        setState(() => _busy = true);
                        try {
                          final repo = await ref.read(
                            contactsRepositoryProvider(widget.tripId).future,
                          );
                          await repo.decline(p.requestId!);
                          ref.invalidate(
                            incomingRequestsProvider(widget.tripId),
                          );
                          await _load();
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                    ),
                  ],
                ),
    );
  }
}

class _ConnectionSection extends StatelessWidget {
  const _ConnectionSection({
    required this.profile,
    required this.busy,
    required this.onRequest,
    required this.onAccept,
    required this.onDecline,
  });

  final MemberProfile profile;
  final bool busy;
  final VoidCallback onRequest;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  Future<void> _dial(
    String uriScheme,
    String phone,
    BuildContext context,
  ) async {
    final uri = Uri(scheme: uriScheme, path: phone);
    final ok = await launchUrl(uri);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No app available to $uriScheme')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (profile.isConnected) {
      final phone = profile.phone;
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.phone, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CONTACT SHARED',
                        style: textTheme.labelSmall
                            ?.copyWith(color: scheme.primary),
                      ),
                      Text(phone ?? '—', style: textTheme.titleMedium),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy number',
                  onPressed: phone == null
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: phone));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Number copied')),
                          );
                        },
                ),
              ],
            ),
          ),
          if (phone != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _dial('sms', phone, context),
                    icon: const Icon(Icons.message_outlined),
                    label: const Text('Message'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _dial('tel', phone, context),
                    icon: const Icon(Icons.call),
                    label: const Text('Call'),
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    }

    if (profile.isPendingIncoming) {
      return Column(
        children: [
          Text(
            'Wants to share phone numbers with you',
            style: textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onDecline,
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onAccept,
                  child: const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (profile.isPendingOutgoing) {
      return FilledButton.tonalIcon(
        onPressed: null,
        icon: const Icon(Icons.hourglass_top),
        label: const Text('Request sent'),
      );
    }

    // none
    return Column(
      children: [
        FilledButton.icon(
          onPressed: busy ? null : onRequest,
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Request contact'),
        ),
        const SizedBox(height: 8),
        Text(
          'They will see your name and avatar, and can share their number '
          'if they accept. Numbers are only shared for this trip.',
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

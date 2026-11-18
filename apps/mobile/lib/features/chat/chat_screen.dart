import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/env.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/models/message.dart';
import '../../shared/models/trip.dart';
import '../../shared/widgets/user_avatar.dart';
import '../map/live_trip_controller.dart';
import '../profile/me_repository.dart';
import '../trips/trips_repository.dart';
import 'chat_repository.dart';

/// Quick-reaction emoji set offered on long-press.
const List<String> kReactionEmojis = ['👍', '❤️', '😂', '🔥', '👏', '😮', '🙏'];

/// Trip group chat. History is paged from REST and live messages stream
/// from the trip WebSocket via [LiveTripController.chatStream]. Sending
/// goes through the WS so all peers see it instantly with no round-trip.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<Map<String, dynamic>>? _liveSub;
  final List<MessageDto> _live = [];
  // Client message ids already rendered — a message can arrive over the mesh
  // and again as the server echo after reconnect; show it once.
  final Set<String> _seenCids = {};
  Timer? _typingIdleTimer;
  bool _typingActive = false;

  // Live reaction overlay (messageId -> {emoji: count}) and my own emojis,
  // kept current by 'reaction' frames + optimistic toggles.
  final Map<String, Map<String, int>> _reactionCounts = {};
  final Map<String, Set<String>> _myReactions = {};

  /// True while a send is in flight — the send button swaps to a
  /// spinner and the button is disabled to prevent double-submits.
  bool _sending = false;

  /// Mirrors whether the input has any non-whitespace content, so
  /// the send button can disable without a full rebuild per keystroke.
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    // Subscribe to the existing trip WebSocket via the live controller —
    // we deliberately don't open a second connection per chat screen.
    final controller = ref.read(liveTripProvider(widget.tripId).notifier);
    _liveSub = controller.chatStream.listen(_onLiveFrame);
    _input.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    final controller = ref.read(liveTripProvider(widget.tripId).notifier);
    final hasText = _input.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
    if (hasText && !_typingActive) {
      _typingActive = true;
      controller.sendTyping(start: true);
    }
    _typingIdleTimer?.cancel();
    if (hasText) {
      _typingIdleTimer = Timer(const Duration(seconds: 3), () {
        _typingActive = false;
        controller.sendTyping(start: false);
      });
    } else if (_typingActive) {
      _typingActive = false;
      controller.sendTyping(start: false);
    }
  }

  void _onLiveFrame(Map<String, dynamic> frame) {
    final type = frame['type'] as String?;
    if (type == 'reaction') {
      final mid = frame['message_id'] as String?;
      if (mid == null) return;
      final counts = (frame['counts'] as Map?)?.map(
            (k, v) => MapEntry(k as String, (v as num).toInt()),
          ) ??
          const <String, int>{};
      final myId = ref.read(meProvider).valueOrNull?.id;
      setState(() {
        _reactionCounts[mid] = counts;
        if (frame['user_id'] == myId) {
          final emoji = frame['emoji'] as String?;
          if (emoji != null) {
            final mine = _myReactions.putIfAbsent(mid, () => <String>{});
            frame['added'] == true ? mine.add(emoji) : mine.remove(emoji);
          }
        }
      });
      return;
    }
    if (type == 'message') {
      // The server echoes our own message back to us; we already rendered an
      // optimistic copy in _send, so skip the echo to avoid a duplicate.
      final fromId = frame['user_id'] as String?;
      final myId = ref.read(meProvider).valueOrNull?.id;
      if (fromId != null && myId != null && fromId == myId) return;
      // De-dup mesh delivery vs. the later server echo by client id.
      final cid = frame['cid'] as String?;
      if (cid != null) {
        if (_seenCids.contains(cid)) return;
        _seenCids.add(cid);
      }
      setState(() {
        _live.add(
          MessageDto(
            id: frame['id'] as String? ??
                'live-${DateTime.now().microsecondsSinceEpoch}',
            tripId: widget.tripId,
            userId: frame['user_id'] as String? ?? '',
            body: frame['body'] as String? ?? '',
            kind: frame['kind'] as String? ?? 'text',
            sentAt: DateTime.now().toUtc(),
            displayName: frame['display_name'] as String?,
            avatarUrl: frame['avatar_url'] as String?,
            attachmentKind: frame['attachment_kind'] as String?,
            attachmentUrl: frame['attachment_url'] as String?,
          ),
        );
      });
    } else if (type == 'arrival') {
      setState(() {
        _live.add(
          MessageDto(
            id: 'live-${DateTime.now().microsecondsSinceEpoch}',
            tripId: widget.tripId,
            userId: frame['user_id'] as String? ?? '',
            body: 'arrived at ${frame['waypoint_name'] ?? 'a waypoint'}',
            kind: 'arrival',
            sentAt: DateTime.now().toUtc(),
          ),
        );
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  /// Send a preset quick-status message (the chat quick-action chips).
  Future<void> _sendQuick(String text) async {
    if (_sending) return;
    _input.text = text;
    _hasText = true;
    await _send();
  }

  Future<void> _send() async {
    if (_sending) return;
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    _input.clear();
    _hasText = false;
    _typingIdleTimer?.cancel();
    final controller = ref.read(liveTripProvider(widget.tripId).notifier);
    if (_typingActive) {
      _typingActive = false;
      controller.sendTyping(start: false);
    }
    try {
      final sentLive = await controller.sendChat(text);
      if (!mounted) return;
      // Optimistic local echo so the sender sees it immediately even
      // if the WS round-trip back is slightly behind. Keyed on the real
      // user id so bubble alignment picks it up as "mine" via meProvider.
      final me = ref.read(meProvider).valueOrNull;
      setState(() {
        _live.add(
          MessageDto(
            id: 'me-${DateTime.now().microsecondsSinceEpoch}',
            tripId: widget.tripId,
            userId: me?.id ?? '',
            body: text,
            kind: 'text',
            sentAt: DateTime.now().toUtc(),
          ),
        );
      });
      _scrollToBottom();
      if (!sentLive) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Offline — message queued, will send when reconnected'),
          ),
        );
      }
    } catch (e) {
      // Restore the text so the user can retry without retyping.
      _input.text = text;
      _hasText = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send message: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ---- Attachments (photo / video / file / location) ----

  Future<void> _attach() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('Photo'),
              onTap: () => Navigator.pop(ctx, 'photo'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Video'),
              onTap: () => Navigator.pop(ctx, 'video'),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text('File'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: const Text('Location'),
              onTap: () => Navigator.pop(ctx, 'location'),
            ),
          ],
        ),
      ),
    );
    switch (choice) {
      case 'photo':
        final x = await ImagePicker()
            .pickImage(source: ImageSource.gallery, imageQuality: 85);
        if (x != null) await _upload(x.path);
      case 'video':
        final x = await ImagePicker().pickVideo(source: ImageSource.gallery);
        if (x != null) await _upload(x.path);
      case 'file':
        final res = await FilePicker.pickFiles();
        final path = res?.files.single.path;
        if (path != null) await _upload(path);
      case 'location':
        await _shareLocation();
    }
  }

  Future<void> _upload(String path) async {
    setState(() => _sending = true);
    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      final msg = await repo.sendAttachment(widget.tripId, path);
      if (!mounted) return;
      setState(() => _live.add(msg));
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _shareLocation() async {
    setState(() => _sending = true);
    try {
      final pos = await Geolocator.getCurrentPosition();
      final repo = await ref.read(chatRepositoryProvider.future);
      final msg = await repo.sendLocation(
        widget.tripId,
        pos.latitude,
        pos.longitude,
      );
      if (!mounted) return;
      setState(() => _live.add(msg));
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not share location: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _typingLabel(Set<String> typing, TripDto? trip) {
    if (trip == null) {
      return typing.length == 1 ? 'typing…' : '${typing.length} typing…';
    }
    final names = <String>[];
    for (final id in typing) {
      for (final m in trip.members) {
        if (m.userId == id) {
          names.add(m.label.split(' ').first);
          break;
        }
      }
    }
    if (names.isEmpty) {
      return typing.length == 1 ? 'Someone is typing…' : 'Several are typing…';
    }
    if (names.length == 1) return '${names.first} is typing…';
    if (names.length == 2) return '${names[0]} and ${names[1]} are typing…';
    return '${names[0]}, ${names[1]} +${names.length - 2} are typing…';
  }

  // ---- Reactions ----

  Map<String, int> _effCounts(MessageDto m) =>
      _reactionCounts[m.id] ?? m.reactions;
  Set<String> _effMine(MessageDto m) => _myReactions[m.id] ?? m.myReactions;

  void _showReactionPicker(MessageDto m) {
    if (m.id.startsWith('live-')) return; // own just-sent, no server id yet
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final e in kReactionEmojis)
                IconButton(
                  iconSize: 28,
                  onPressed: () {
                    Navigator.pop(ctx);
                    _toggleReaction(m, e);
                  },
                  icon: Text(e, style: const TextStyle(fontSize: 26)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleReaction(MessageDto m, String emoji) async {
    if (m.id.startsWith('live-')) return;
    // Optimistic update.
    final counts = Map<String, int>.from(_effCounts(m));
    final mine = Set<String>.from(_effMine(m));
    if (mine.contains(emoji)) {
      mine.remove(emoji);
      final n = (counts[emoji] ?? 1) - 1;
      n <= 0 ? counts.remove(emoji) : counts[emoji] = n;
    } else {
      mine.add(emoji);
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }
    setState(() {
      _reactionCounts[m.id] = counts;
      _myReactions[m.id] = mine;
    });
    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      final res = await repo.toggleReaction(widget.tripId, m.id, emoji);
      final serverCounts = (res['counts'] as Map?)?.map(
            (k, v) => MapEntry(k as String, (v as num).toInt()),
          ) ??
          const <String, int>{};
      if (mounted) setState(() => _reactionCounts[m.id] = serverCounts);
    } catch (_) {
      if (mounted) ref.invalidate(chatHistoryProvider(widget.tripId));
    }
  }

  @override
  void dispose() {
    _typingIdleTimer?.cancel();
    _input.removeListener(_onInputChanged);
    _liveSub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(chatHistoryProvider(widget.tripId));
    final live = ref.watch(liveTripProvider(widget.tripId));
    final typing = live.typingUserIds;
    final currentUserId = ref.watch(meProvider).valueOrNull?.id;
    final tripAsync = ref.watch(tripDetailProvider(widget.tripId));
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final trip = tripAsync.valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              trip?.name ?? 'Trip chat',
              style: textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
            if (trip != null)
              Text(
                '${live.onlineUserIds.length} ACTIVE · '
                '${trip.members.length} '
                'member${trip.members.length == 1 ? '' : 's'}',
                style: textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (!live.connected)
            Material(
              color: scheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.bluetooth,
                      size: 16,
                      color: scheme.onTertiaryContainer,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        live.nearbyPeers > 0
                            ? 'Offline — messaging ${live.nearbyPeers} nearby '
                                'member${live.nearbyPeers == 1 ? '' : 's'} over Bluetooth'
                            : 'Offline — looking for nearby members over Bluetooth…',
                        style: textTheme.labelMedium?.copyWith(
                          color: scheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: historyAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ChatErrorState(
                message: '$e',
                onRetry: () =>
                    ref.invalidate(chatHistoryProvider(widget.tripId)),
              ),
              data: (history) {
                // Drop optimistic / mesh entries from the live buffer that the
                // server history already contains (matched on sender+body), so
                // a message doesn't render twice when history is (re)fetched
                // while the live buffer still holds the same logical message.
                final seen = <String>{
                  for (final m in history) '${m.userId}\u0000${m.body}',
                };
                final liveUnique = _live
                    .where((m) => seen.add('${m.userId}\u0000${m.body}'))
                    .toList();
                final all = [...history, ...liveUnique];
                if (all.isEmpty) {
                  return const _ChatEmptyState();
                }
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.md,
                  ),
                  itemCount: all.length,
                  itemBuilder: (_, i) {
                    final message = all[i];
                    final previous = i > 0 ? all[i - 1] : null;
                    final next = i < all.length - 1 ? all[i + 1] : null;
                    final isMe = currentUserId != null &&
                        message.userId == currentUserId;
                    final showSender = !message.isSystem &&
                        !isMe &&
                        (previous == null ||
                            previous.isSystem ||
                            previous.userId != message.userId);
                    final showTail = !message.isSystem &&
                        (next == null ||
                            next.isSystem ||
                            next.userId != message.userId);
                    return _MessageBubble(
                      message: message,
                      isMe: isMe,
                      showSender: showSender,
                      showTail: showTail,
                      reactions: _effCounts(message),
                      myReactions: _effMine(message),
                      onLongPress: () => _showReactionPicker(message),
                      onToggleReaction: (e) => _toggleReaction(message, e),
                    );
                  },
                );
              },
            ),
          ),
          if (typing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _typingLabel(typing, trip),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          _QuickActions(onSend: _sendQuick),
          _InputBar(
            controller: _input,
            hasText: _hasText,
            sending: _sending,
            onSend: _send,
            onAttach: _attach,
          ),
        ],
      ),
    );
  }
}

/// Quick-status chips above the composer (from designs/pack_chat): one-tap
/// pack signals that post as ordinary messages.
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onSend});
  final void Function(String) onSend;

  static const _items = <(IconData, String, String)>[
    (Icons.local_gas_station, 'Need gas', '⛽ Need gas soon'),
    (Icons.local_cafe, 'Rest stop', '☕ Rest stop?'),
    (Icons.local_police, 'Police', '🚓 Police ahead'),
    (Icons.warning_amber_rounded, 'Hazard', '⚠️ Hazard ahead'),
    (Icons.flag, 'Regroup', '📍 Let\'s regroup'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, i) {
          final (icon, label, message) = _items[i];
          return ActionChip(
            avatar: Icon(icon, size: 16, color: scheme.primary),
            label: Text(label),
            backgroundColor: scheme.surfaceContainerHigh,
            side: BorderSide.none,
            onPressed: () => onSend(message),
          );
        },
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.showSender,
    required this.showTail,
    this.reactions = const {},
    this.myReactions = const {},
    this.onLongPress,
    this.onToggleReaction,
  });

  final MessageDto message;
  final Map<String, int> reactions;
  final Set<String> myReactions;
  final VoidCallback? onLongPress;
  final void Function(String emoji)? onToggleReaction;

  /// True when the current user sent this message — aligned end, uses
  /// `colorScheme.primary` on `onPrimary`.
  final bool isMe;

  /// True when the preceding message is from a different sender — show
  /// the sender label above the bubble. Only meaningful for incoming.
  final bool showSender;

  /// True when the following message is from a different sender — show
  /// the timestamp below the bubble. Squares off the "attached" corner
  /// on the vertical edge that faces this sender.
  final bool showTail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Marshall broadcast — a prominent full-width card, not a text bubble.
    if (message.kind == 'announcement') {
      return Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm,
          horizontal: AppSpacing.xs,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer,
            borderRadius: AppRadii.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.campaign,
                      size: 18, color: scheme.onTertiaryContainer),
                  const SizedBox(width: 6),
                  Text(
                    'Marshall · ${message.senderLabel}',
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onTertiaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                message.body,
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onTertiaryContainer,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xs,
          horizontal: AppSpacing.base,
        ),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: AppRadii.full,
            ),
            child: Text(
              message.body,
              style: textTheme.labelSmall?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
        ),
      );
    }

    // Square off the corner attached to the edge of the screen on the
    // last message in a run from this sender — classic chat-bubble tail.
    final radius = BorderRadius.only(
      topLeft: AppRadii.lg.topLeft,
      topRight: AppRadii.lg.topRight,
      bottomLeft:
          showTail && isMe ? AppRadii.lg.bottomLeft : AppRadii.xs.bottomLeft,
      bottomRight:
          showTail && !isMe ? AppRadii.lg.bottomRight : AppRadii.xs.bottomRight,
    );

    final bubbleColor = isMe ? scheme.primary : scheme.surfaceContainerHigh;
    final textColor = isMe ? scheme.onPrimary : scheme.onSurface;
    final topGap = showSender ? AppSpacing.sm : AppSpacing.xs;

    return Padding(
      padding: EdgeInsets.only(top: topGap),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showSender)
                Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.xs,
                    bottom: 3,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      UserAvatar(
                        name: message.senderLabel,
                        avatarUrl: message.avatarUrl,
                        radius: 10,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        message.senderLabel,
                        style: textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              GestureDetector(
                onLongPress: onLongPress,
                child: Container(
                  padding:
                      message.hasAttachment && message.attachmentKind == 'image'
                          ? const EdgeInsets.all(4)
                          : const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.sm,
                            ),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: radius,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.hasAttachment)
                        _buildAttachment(context, textColor),
                      if (message.body.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(
                            top: message.hasAttachment ? AppSpacing.xs : 0,
                            left: message.attachmentKind == 'image' ? 6 : 0,
                            right: message.attachmentKind == 'image' ? 6 : 0,
                            bottom: message.attachmentKind == 'image' ? 4 : 0,
                          ),
                          child: Text(
                            message.body,
                            style: textTheme.bodyMedium
                                ?.copyWith(color: textColor),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (reactions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Wrap(
                    spacing: 4,
                    children: [
                      for (final entry in reactions.entries)
                        _ReactionChip(
                          emoji: entry.key,
                          count: entry.value,
                          mine: myReactions.contains(entry.key),
                          onTap: () => onToggleReaction?.call(entry.key),
                        ),
                    ],
                  ),
                ),
              if (showTail)
                Padding(
                  padding: const EdgeInsets.only(
                    top: 2,
                    left: AppSpacing.sm,
                    right: AppSpacing.sm,
                  ),
                  child: Text(
                    DateFormat.Hm().format(message.sentAt.toLocal()),
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Resolves a stored `/media/...` path to a full URL on the API host.
  String _mediaUrl(String path) =>
      path.startsWith('http') ? path : '${Env.apiBaseUrl}$path';

  Widget _buildAttachment(BuildContext context, Color textColor) {
    final url = message.attachmentUrl!;
    switch (message.attachmentKind) {
      case 'image':
        return ClipRRect(
          borderRadius: AppRadii.lg,
          child: Image.network(
            _mediaUrl(url),
            width: 220,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fileChip(
              context,
              textColor,
              Icons.broken_image_outlined,
              'Image unavailable',
            ),
            loadingBuilder: (c, child, progress) => progress == null
                ? child
                : const SizedBox(
                    width: 220,
                    height: 140,
                    child: Center(child: CircularProgressIndicator()),
                  ),
          ),
        );
      case 'video':
        return GestureDetector(
          onTap: () => launchUrl(
            Uri.parse(_mediaUrl(url)),
            mode: LaunchMode.externalApplication,
          ),
          child: Container(
            width: 220,
            height: 130,
            decoration: const BoxDecoration(
              color: Colors.black26,
              borderRadius: AppRadii.lg,
            ),
            child: const Center(
              child:
                  Icon(Icons.play_circle_fill, size: 48, color: Colors.white),
            ),
          ),
        );
      case 'location':
        final parts = url.split(',');
        final lat = parts.isNotEmpty ? parts[0] : '';
        final lng = parts.length > 1 ? parts[1] : '';
        return GestureDetector(
          onTap: () => launchUrl(
            Uri.parse(
                'https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
            mode: LaunchMode.externalApplication,
          ),
          child: _fileChip(
            context,
            textColor,
            Icons.location_on,
            'Shared location',
          ),
        );
      case 'file':
      default:
        return GestureDetector(
          onTap: () => launchUrl(
            Uri.parse(_mediaUrl(url)),
            mode: LaunchMode.externalApplication,
          ),
          child: _fileChip(
            context,
            textColor,
            Icons.insert_drive_file,
            url.split('/').last,
          ),
        );
    }
  }

  Widget _fileChip(
    BuildContext context,
    Color textColor,
    IconData icon,
    String label,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22, color: textColor),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: textColor, decoration: TextDecoration.underline),
          ),
        ),
      ],
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.emoji,
    required this.count,
    required this.mine,
    required this.onTap,
  });

  final String emoji;
  final int count;
  final bool mine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.full,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color:
              mine ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: AppRadii.full,
          border: mine ? Border.all(color: scheme.primary, width: 1) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 3),
            Text(
              '$count',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: mine
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatEmptyState extends StatelessWidget {
  const _ChatEmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline,
                color: scheme.onSurfaceVariant,
                size: 32,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('No messages yet', style: textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Say hi to the group. Messages appear here.',
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

class _ChatErrorState extends StatelessWidget {
  const _ChatErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: scheme.error),
            const SizedBox(height: AppSpacing.md),
            Text("Couldn't load messages", style: textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              style: textTheme.bodySmall?.copyWith(
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

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.hasText,
    required this.sending,
    required this.onSend,
    required this.onAttach,
  });

  final TextEditingController controller;
  final bool hasText;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final canSend = hasText && !sending;
    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                onPressed: sending ? null : onAttach,
                icon: const Icon(Icons.add_circle_outline),
                color: scheme.primary,
                tooltip: 'Attach',
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: !sending,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => canSend ? onSend() : null,
                  minLines: 1,
                  maxLines: 5,
                  style: textTheme.bodyMedium,
                  decoration: InputDecoration(
                    hintText: 'Message the pack',
                    hintStyle: textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest,
                    border: const OutlineInputBorder(
                      borderRadius: AppRadii.xl,
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderRadius: AppRadii.xl,
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: AppRadii.xl,
                      borderSide: BorderSide(
                        color: scheme.primary,
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                height: 44,
                width: 44,
                child: Material(
                  color:
                      canSend ? scheme.primary : scheme.surfaceContainerHighest,
                  borderRadius: AppRadii.round,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: canSend ? onSend : null,
                    child: Center(
                      child: sending
                          ? SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: scheme.onPrimary,
                              ),
                            )
                          : Icon(
                              Icons.send,
                              size: 20,
                              color: canSend
                                  ? scheme.onPrimary
                                  : scheme.onSurfaceVariant,
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

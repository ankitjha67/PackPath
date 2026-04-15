import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/models/message.dart';
import '../map/live_trip_controller.dart';
import '../profile/me_repository.dart';
import '../trips/trips_repository.dart';
import 'chat_repository.dart';

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
  Timer? _typingIdleTimer;
  bool _typingActive = false;

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
    if (type == 'message') {
      setState(() {
        _live.add(
          MessageDto(
            id: 'live-${DateTime.now().microsecondsSinceEpoch}',
            tripId: widget.tripId,
            userId: frame['user_id'] as String? ?? '',
            body: frame['body'] as String? ?? '',
            kind: 'text',
            sentAt: DateTime.now().toUtc(),
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
      controller.sendChat(text);
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
                '${trip.members.length} '
                'member${trip.members.length == 1 ? '' : 's'}',
                style: textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: historyAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ChatErrorState(
                message: '$e',
                onRetry: () =>
                    ref.invalidate(chatHistoryProvider(widget.tripId)),
              ),
              data: (history) {
                final all = [...history, ..._live];
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
                  typing.length == 1
                      ? 'Someone is typing…'
                      : '${typing.length} people are typing…',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          _InputBar(
            controller: _input,
            hasText: _hasText,
            sending: _sending,
            onSend: _send,
          ),
        ],
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
  });

  final MessageDto message;

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
                    left: AppSpacing.sm,
                    bottom: 2,
                  ),
                  child: Text(
                    _senderLabel(message.userId),
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: radius,
                ),
                child: Text(
                  message.body,
                  style: textTheme.bodyMedium?.copyWith(color: textColor),
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

  String _senderLabel(String userId) {
    if (userId.isEmpty) return 'Unknown';
    return userId.substring(0, userId.length < 8 ? userId.length : 8);
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
  });

  final TextEditingController controller;
  final bool hasText;
  final bool sending;
  final VoidCallback onSend;

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

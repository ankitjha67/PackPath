import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_spacing.dart';
import '../../shared/models/message.dart';
import '../map/live_trip_controller.dart';
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
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    _typingIdleTimer?.cancel();
    final controller = ref.read(liveTripProvider(widget.tripId).notifier);
    if (_typingActive) {
      _typingActive = false;
      controller.sendTyping(start: false);
    }
    controller.sendChat(text);
    // Optimistic local echo so the sender sees it immediately even if the
    // WS round-trip back is slightly behind.
    setState(() {
      _live.add(
        MessageDto(
          id: 'me-${DateTime.now().microsecondsSinceEpoch}',
          tripId: widget.tripId,
          userId: 'me',
          body: text,
          kind: 'text',
          sentAt: DateTime.now().toUtc(),
        ),
      );
    });
    _scrollToBottom();
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
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
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
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: all.length,
                  itemBuilder: (_, i) => _MessageBubble(message: all[i]),
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
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Message the pack',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final MessageDto message;

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              message.body,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            child: Text(
              message.userId.isEmpty
                  ? '?'
                  : message.userId.substring(0, 1).toUpperCase(),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message.body),
                Text(
                  DateFormat.Hm().format(message.sentAt.toLocal()),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
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

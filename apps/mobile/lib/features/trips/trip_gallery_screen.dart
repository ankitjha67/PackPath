import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/env.dart';
import '../../shared/models/message.dart';
import '../chat/chat_repository.dart';

/// Trip gallery — every photo and video shared in the trip chat, in a grid.
class TripGalleryScreen extends ConsumerWidget {
  const TripGalleryScreen({super.key, required this.tripId});

  final String tripId;

  static String mediaUrl(String path) =>
      path.startsWith('http') ? path : '${Env.apiBaseUrl}$path';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaAsync = ref.watch(tripMediaProvider(tripId));
    return Scaffold(
      appBar: AppBar(title: const Text('Trip gallery')),
      body: mediaAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load gallery: $e')),
        data: (items) {
          if (items.isEmpty) return const _GalleryEmpty();
          return GridView.builder(
            padding: const EdgeInsets.all(2),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) => _GalleryTile(
              message: items[i],
              onTap: () => _open(context, items, i),
            ),
          );
        },
      ),
    );
  }

  void _open(BuildContext context, List<MessageDto> items, int index) {
    final m = items[index];
    if (m.attachmentKind == 'video') {
      launchUrl(
        Uri.parse(mediaUrl(m.attachmentUrl!)),
        mode: LaunchMode.externalApplication,
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PhotoViewer(items: items, initialIndex: index),
      ),
    );
  }
}

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({required this.message, required this.onTap});

  final MessageDto message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final url = TripGalleryScreen.mediaUrl(message.attachmentUrl!);
    final isVideo = message.attachmentKind == 'video';
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (isVideo)
            Container(
              color: Colors.black87,
              child:
                  const Icon(Icons.videocam, color: Colors.white70, size: 32),
            )
          else
            Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.broken_image_outlined),
              ),
              loadingBuilder: (c, child, progress) => progress == null
                  ? child
                  : Container(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
            ),
          if (isVideo)
            const Center(
              child:
                  Icon(Icons.play_circle_fill, color: Colors.white, size: 36),
            ),
        ],
      ),
    );
  }
}

/// Swipeable full-screen photo viewer with pinch-to-zoom.
class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.items, required this.initialIndex});

  final List<MessageDto> items;
  final int initialIndex;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.items[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(current.senderLabel),
        elevation: 0,
      ),
      body: PageView.builder(
        controller: _controller,
        onPageChanged: (i) => setState(() => _index = i),
        itemCount: widget.items.length,
        itemBuilder: (_, i) {
          final m = widget.items[i];
          return InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(
              child: Image.network(
                TripGalleryScreen.mediaUrl(m.attachmentUrl!),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                  size: 48,
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: current.body.isEmpty
          ? null
          : Container(
              color: Colors.black,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              width: double.infinity,
              child: Text(
                current.body,
                style: const TextStyle(color: Colors.white),
              ),
            ),
    );
  }
}

class _GalleryEmpty extends StatelessWidget {
  const _GalleryEmpty();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.photo_library_outlined,
              size: 48, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('No photos yet', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Photos and videos shared in chat appear here.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

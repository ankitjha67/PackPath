import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import 'documents_repository.dart';

/// Document vault: shared trip documents as links (permits, bookings) and
/// notes (reference numbers, instructions). Any member can add; the uploader
/// or marshall can remove.
class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key, required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final async = ref.watch(tripDocumentsProvider(tripId));
    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
        data: (docs) {
          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'No documents yet. Add permit links, booking references and '
                  'notes the whole pack can reach.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.base),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) {
              final d = docs[i];
              final isLink = d.kind == 'link';
              return Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: AppRadii.lg,
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(
                      isLink ? Icons.link : Icons.sticky_note_2,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  title: Text(d.title, style: textTheme.titleMedium),
                  subtitle: Text(
                    isLink ? (d.url ?? '') : (d.body ?? ''),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(context, ref, d.id),
                  ),
                  onTap: isLink && d.url != null
                      ? () => _open(context, d.url!)
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not open $url')));
    }
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    var kind = 'link';
    final titleCtrl = TextEditingController();
    final valueCtrl = TextEditingController();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.base,
          right: AppSpacing.base,
          top: AppSpacing.base,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.base,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add document', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'link',
                    label: Text('Link'),
                    icon: Icon(Icons.link),
                  ),
                  ButtonSegment(
                    value: 'note',
                    label: Text('Note'),
                    icon: Icon(Icons.sticky_note_2),
                  ),
                ],
                selected: {kind},
                onSelectionChanged: (s) => setSheet(() => kind = s.first),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: titleCtrl,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              TextField(
                controller: valueCtrl,
                maxLines: kind == 'note' ? 4 : 1,
                keyboardType: kind == 'link'
                    ? TextInputType.url
                    : TextInputType.multiline,
                decoration: InputDecoration(
                  labelText: kind == 'link' ? 'URL' : 'Note text',
                  hintText:
                      kind == 'link' ? 'https://…' : 'e.g. Booking #ABC123',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Add'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true ||
        titleCtrl.text.trim().isEmpty ||
        valueCtrl.text.trim().isEmpty) {
      return;
    }
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(documentsRepositoryProvider.future);
      if (kind == 'link') {
        await repo.addLink(
          tripId: tripId,
          title: titleCtrl.text.trim(),
          url: valueCtrl.text.trim(),
        );
      } else {
        await repo.addNote(
          tripId: tripId,
          title: titleCtrl.text.trim(),
          body: valueCtrl.text.trim(),
        );
      }
      ref.invalidate(tripDocumentsProvider(tripId));
      messenger.showSnackBar(const SnackBar(content: Text('Document added')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not add: $e')));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, String id) async {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(documentsRepositoryProvider.future);
      await repo.delete(tripId: tripId, documentId: id);
      ref.invalidate(tripDocumentsProvider(tripId));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    }
  }
}

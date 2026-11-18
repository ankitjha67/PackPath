import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../map/live_trip_controller.dart';
import '../profile/me_repository.dart';
import 'checklist_repository.dart';

/// Phase 6 — the shared, live trip checklist. Everyone sees the same list of
/// things to pack, buy, and do; items can be claimed ("I've got it"), checked
/// off, and deleted, all synced live across the pack.
class ChecklistScreen extends ConsumerStatefulWidget {
  const ChecklistScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends ConsumerState<ChecklistScreen> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo =
          await ref.read(checklistRepositoryProvider(widget.tripId).future);
      final items = await repo.list();
      if (!mounted) return;
      ref
          .read(liveTripProvider(widget.tripId).notifier)
          .seedChecklist([for (final i in items) i.toJson()]);
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = ref.watch(meProvider).valueOrNull?.id;
    final raw = ref.watch(liveTripProvider(widget.tripId)).checklist;
    final items = raw.values.map((e) => ChecklistItemDto.fromJson(e)).toList()
      ..sort((a, b) {
        if (a.done != b.done) return a.done ? 1 : -1;
        return 0;
      });
    final total = items.length;
    final done = items.where((i) => i.done).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip checklist'),
        bottom: total == 0
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : done / total,
                  minHeight: 4,
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : total == 0
                  ? const _Empty()
                  : _GroupedList(
                      items: items,
                      myId: myId,
                      onToggle: _toggle,
                      onClaim: _claim,
                      onDelete: _delete,
                    ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final result = await showModalBottomSheet<_NewItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _AddItemForm(),
    );
    if (result == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo =
          await ref.read(checklistRepositoryProvider(widget.tripId).future);
      final dto = await repo.add(
        title: result.title,
        category: result.category,
        qty: result.qty,
        assignToMe: result.mine,
      );
      _applyLocal(dto);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Could not add: $e')));
    }
  }

  Future<void> _toggle(ChecklistItemDto item) async {
    try {
      final repo =
          await ref.read(checklistRepositoryProvider(widget.tripId).future);
      final dto = await repo.toggle(item.id);
      _applyLocal(dto);
    } catch (e) {
      _snack('Could not update: $e');
    }
  }

  Future<void> _claim(ChecklistItemDto item) async {
    try {
      final repo =
          await ref.read(checklistRepositoryProvider(widget.tripId).future);
      final dto = await repo.claim(item.id);
      _applyLocal(dto);
    } catch (e) {
      _snack('Could not claim: $e');
    }
  }

  Future<void> _delete(ChecklistItemDto item) async {
    try {
      final repo =
          await ref.read(checklistRepositoryProvider(widget.tripId).future);
      await repo.remove(item.id);
      ref
          .read(liveTripProvider(widget.tripId).notifier)
          .removeChecklistLocal(item.id);
    } catch (e) {
      _snack('Could not delete: $e');
    }
  }

  void _applyLocal(ChecklistItemDto dto) {
    ref
        .read(liveTripProvider(widget.tripId).notifier)
        .upsertChecklist(dto.toJson());
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _GroupedList extends StatelessWidget {
  const _GroupedList({
    required this.items,
    required this.myId,
    required this.onToggle,
    required this.onClaim,
    required this.onDelete,
  });

  final List<ChecklistItemDto> items;
  final String? myId;
  final ValueChanged<ChecklistItemDto> onToggle;
  final ValueChanged<ChecklistItemDto> onClaim;
  final ValueChanged<ChecklistItemDto> onDelete;

  @override
  Widget build(BuildContext context) {
    // Group by category, keeping the canonical category order.
    final byCat = <String, List<ChecklistItemDto>>{};
    for (final it in items) {
      byCat.putIfAbsent(it.category, () => []).add(it);
    }
    final cats =
        kChecklistCategories.where((c) => byCat.containsKey(c.id)).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        for (final cat in cats) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.base, AppSpacing.md, AppSpacing.base, AppSpacing.xs),
            child: Row(
              children: [
                Icon(cat.icon, size: 18, color: cat.color),
                const SizedBox(width: AppSpacing.sm),
                Text(cat.label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: cat.color,
                          fontWeight: FontWeight.w700,
                        )),
              ],
            ),
          ),
          for (final item in byCat[cat.id]!)
            _ChecklistTile(
              item: item,
              mine: item.assignedTo != null && item.assignedTo == myId,
              onToggle: () => onToggle(item),
              onClaim: () => onClaim(item),
              onDelete: () => onDelete(item),
            ),
        ],
      ],
    );
  }
}

class _ChecklistTile extends StatelessWidget {
  const _ChecklistTile({
    required this.item,
    required this.mine,
    required this.onToggle,
    required this.onClaim,
    required this.onDelete,
  });

  final ChecklistItemDto item;
  final bool mine;
  final VoidCallback onToggle;
  final VoidCallback onClaim;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        color: scheme.errorContainer,
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        child: Icon(Icons.delete, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) => onDelete(),
      child: ListTile(
        leading: Checkbox(
          value: item.done,
          onChanged: (_) => onToggle(),
        ),
        title: Text(
          item.qty > 1 ? '${item.title}  ×${item.qty}' : item.title,
          style: TextStyle(
            decoration: item.done ? TextDecoration.lineThrough : null,
            color: item.done ? scheme.onSurfaceVariant : null,
          ),
        ),
        subtitle: item.assigneeName != null
            ? Text(
                '${mine ? "You" : item.assigneeName} ${item.done ? "got it" : "has this"}')
            : null,
        trailing: TextButton.icon(
          onPressed: onClaim,
          icon: Icon(
            mine ? Icons.person : Icons.pan_tool_alt_outlined,
            size: 16,
          ),
          label: Text(mine
              ? 'Release'
              : (item.assignedTo == null ? "I've got it" : 'Take over')),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.checklist_rtl, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.sm),
            Text('Nothing on the list yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Add what the pack needs to pack, buy, or do. Everyone can claim '
              'items and check them off — it all syncs live.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: AppSpacing.sm),
            Text('Could not load the checklist',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
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

class _NewItem {
  const _NewItem(this.title, this.category, this.qty, this.mine);
  final String title;
  final String category;
  final int qty;
  final bool mine;
}

class _AddItemForm extends StatefulWidget {
  const _AddItemForm();

  @override
  State<_AddItemForm> createState() => _AddItemFormState();
}

class _AddItemFormState extends State<_AddItemForm> {
  final _title = TextEditingController();
  String _category = 'packing';
  int _qty = 1;
  bool _mine = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.base,
          right: AppSpacing.base,
          top: AppSpacing.base,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.base,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add to checklist',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _title,
              autofocus: true,
              maxLength: 160,
              decoration: const InputDecoration(
                labelText: 'What',
                hintText: 'e.g. First-aid kit',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in kChecklistCategories)
                  ChoiceChip(
                    avatar: Icon(c.icon,
                        size: 16,
                        color: _category == c.id ? Colors.white : c.color),
                    label: Text(c.label),
                    selected: _category == c.id,
                    selectedColor: c.color,
                    labelStyle: TextStyle(
                        color: _category == c.id ? Colors.white : null),
                    onSelected: (_) => setState(() => _category = c.id),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const Text('Quantity'),
                const Spacer(),
                IconButton(
                  onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$_qty', style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  onPressed: () => setState(() => _qty++),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _mine,
              onChanged: (v) => setState(() => _mine = v),
              title: const Text("I'll bring this"),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  final title = _title.text.trim();
                  if (title.isEmpty) return;
                  Navigator.pop(
                      context, _NewItem(title, _category, _qty, _mine));
                },
                icon: const Icon(Icons.check),
                label: const Text('Add'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

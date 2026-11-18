import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import 'emergency_contacts_repository.dart';

/// Manage emergency contacts — people the app can text (with your location) if
/// you hit SOS. Stored per user, reused on every trip.
class EmergencyContactsScreen extends ConsumerWidget {
  const EmergencyContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(emergencyContactsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency contacts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add'),
      ),
      body: contactsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
        data: (contacts) {
          if (contacts.isEmpty) {
            return const _Empty();
          }
          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: contacts.length,
            itemBuilder: (_, i) {
              final c = contacts[i];
              return Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(c.name),
                  subtitle: Text(c.phone),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(context, ref, c),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _AddContactForm(),
    );
    if (result == null) return;
    final (name, phone) = result;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(emergencyContactsRepositoryProvider.future);
      await repo.add(name, phone);
      ref.invalidate(emergencyContactsProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not add: $e')));
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    EmergencyContact c,
  ) async {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(emergencyContactsRepositoryProvider.future);
      await repo.delete(c.id);
      ref.invalidate(emergencyContactsProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not remove: $e')));
    }
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
            Icon(
              Icons.contact_phone_outlined,
              size: 48,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'No emergency contacts yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Add family or friends. If you hit SOS, you can text them your '
              'live location in one tap.',
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

class _AddContactForm extends StatefulWidget {
  const _AddContactForm();

  @override
  State<_AddContactForm> createState() => _AddContactFormState();
}

class _AddContactFormState extends State<_AddContactForm> {
  final _name = TextEditingController();
  final _phone = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add emergency contact',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () {
                final name = _name.text.trim();
                final phone = _phone.text.trim();
                if (name.isEmpty || phone.length < 3) return;
                Navigator.pop(context, (name, phone));
              },
              child: const Text('Save contact'),
            ),
          ],
        ),
      ),
    );
  }
}

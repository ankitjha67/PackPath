import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';

/// Read-only audit log of who looked at the user's location, when, and
/// what action they took. Backed by /me/audit.
class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auditAsync = ref.watch(_auditProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Audit log')),
      body: auditAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rows) => rows.isEmpty
            ? const Center(child: Text('Nothing logged yet'))
            : ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = rows[i];
                  final when = DateTime.parse(r['created_at'] as String);
                  return ListTile(
                    leading: const Icon(Icons.shield_outlined),
                    title: Text(r['action'] as String),
                    subtitle: Text(
                      DateFormat.yMMMd().add_Hm().format(when.toLocal()),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

final _auditProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final dio = await ref.watch(apiClientProvider.future);
  final response = await dio.get('/me/audit');
  return (response.data as List).cast<Map<String, dynamic>>();
});

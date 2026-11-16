import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';

/// Trip expenses + cost split. Lists every expense, lets the user add a
/// new one, and shows the per-member balance bar at the bottom.
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  Future<void> _add(BuildContext context) async {
    // The dialog owns its TextEditingControllers and disposes them in its own
    // State.dispose(), so a controller is never torn down while its TextField
    // is still mounted. Disposing them here in _add() (after showDialog) raced
    // the dialog's exit/keyboard-driven rebuild and threw "ChangeNotifier used
    // after dispose" + a RenderFlex overflow, crashing the screen.
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => const _AddExpenseDialog(),
    );
    if (result == null) return;
    final desc = result.$1.trim();
    // Accept decimals ("99.50") — int.tryParse silently dropped them.
    final amountValue = double.tryParse(result.$2.trim());
    if (desc.isEmpty || amountValue == null || amountValue <= 0) return;
    try {
      final dio = await ref.read(apiClientProvider.future);
      await dio.post(
        '/trips/${widget.tripId}/expenses',
        data: {
          'description': desc,
          'amount_cents': (amountValue * 100).round(),
          'currency': 'INR',
          'category': 'other',
        },
      );
      ref.invalidate(_expensesProvider(widget.tripId));
      ref.invalidate(_balancesProvider(widget.tripId));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add expense: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final expensesAsync = ref.watch(_expensesProvider(widget.tripId));
    final balancesAsync = ref.watch(_balancesProvider(widget.tripId));
    // decimalDigits: 2 so entered paise (e.g. 99.50) and fractional net
    // balances aren't rounded to whole rupees at display time.
    final money = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: Column(
        children: [
          Expanded(
            child: expensesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (rows) => rows.isEmpty
                  ? const Center(child: Text('No expenses logged yet'))
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = rows[i];
                        return ListTile(
                          leading: const Icon(Icons.receipt_long),
                          title: Text(e['description'] as String),
                          subtitle: Text(
                            'Paid by ${(e['paid_by'] as String).substring(0, 6)}',
                          ),
                          trailing: Text(
                            money.format((e['amount_cents'] as int) / 100),
                          ),
                        );
                      },
                    ),
            ),
          ),
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: balancesAsync.when(
                loading: () => const Text('Computing balances…'),
                error: (e, _) => Text('Error: $e'),
                data: (bal) {
                  final list = (bal['balances'] as List?) ?? const [];
                  if (list.isEmpty) return const Text('No balances yet');
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Balances',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      for (final b in list)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '…${(b['user_id'] as String).substring(0, 6)}',
                                ),
                              ),
                              Text(
                                money.format(
                                  ((b['net_cents'] as int)) / 100,
                                ),
                                style: TextStyle(
                                  color: ((b['net_cents'] as int)) >= 0
                                      ? Colors.green
                                      : Colors.red,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final _expensesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, tripId) async {
    ref.watch(sessionEpochProvider);
    final dio = await ref.watch(apiClientProvider.future);
    final response = await dio.get('/trips/$tripId/expenses');
    return (response.data as List).cast<Map<String, dynamic>>();
  },
);

final _balancesProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, tripId) async {
  ref.watch(sessionEpochProvider);
  final dio = await ref.watch(apiClientProvider.future);
  final response = await dio.get('/trips/$tripId/expenses/balances');
  return response.data as Map<String, dynamic>;
});

/// Add-expense dialog. Owns its text controllers so they live and die with the
/// dialog subtree (disposed in [State.dispose]); `scrollable: true` lets the
/// content scroll when the soft keyboard shrinks the available height instead
/// of overflowing. Returns `(description, amount)` on confirm, null on cancel.
class _AddExpenseDialog extends StatefulWidget {
  const _AddExpenseDialog();

  @override
  State<_AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<_AddExpenseDialog> {
  final _descController = TextEditingController();
  final _amountController = TextEditingController();

  @override
  void dispose() {
    _descController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Add expense'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _descController,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          TextField(
            controller: _amountController,
            // numberWithOptions(decimal: true) is required for the Android
            // soft keyboard to offer a decimal point; plain
            // TextInputType.number renders a digits-only pad, so "99.50"
            // could never be typed.
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: const InputDecoration(labelText: 'Amount (₹)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            (_descController.text, _amountController.text),
          ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

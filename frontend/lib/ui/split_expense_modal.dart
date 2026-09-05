import 'package:flutter/material.dart';
import '../domain/transaction_item.dart';
import '../services/peer_debt_service.dart';

class SplitExpenseModal extends StatefulWidget {
  final TransactionItem transaction;
  final VoidCallback? onCompleted;

  const SplitExpenseModal({
    super.key,
    required this.transaction,
    this.onCompleted,
  });

  @override
  State<SplitExpenseModal> createState() => _SplitExpenseModalState();
}

class _SplitExpenseModalState extends State<SplitExpenseModal> {
  int _selectedMode = 0; // 0 = 100% Lent, 1 = Custom Split
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  // For split mode
  final List<Map<String, dynamic>> _splitRows = [
    {'nameController': TextEditingController(), 'amountController': TextEditingController()},
  ];

  @override
  void dispose() {
    _contactController.dispose;
    _noteController.dispose;
    for (final row in _splitRows) {
      (row['nameController'] as TextEditingController).dispose;
      (row['amountController'] as TextEditingController).dispose;
    }
    super.dispose;
  }

  double get _totalSplitAmount {
    double sum = 0.0;
    for (final row in _splitRows) {
      final text = (row['amountController'] as TextEditingController).text;
      sum += double.tryParse(text) ?? 0.0;
    }
    return sum;
  }

  double get _personalShare => (widget.transaction.amount - _totalSplitAmount).clamp(0.0, widget.transaction.amount);

  void _save100PercentLent() {
    final contact = _contactController.text.trim();
    if (contact.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter contact name')),
      );
      return;
    }

    PeerDebtState().markAs100PercentLent(
      transactionId: widget.transaction.id,
      contactName: contact,
      amount: widget.transaction.amount,
      merchantName: widget.transaction.merchantName,
      currency: widget.transaction.currency,
    );

    Navigator.of(context).pop();
    widget.onCompleted?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Marked 100% lent to $contact ($widget.transaction.currency ${widget.transaction.amount.toStringAsFixed(2)})')),
    );
  }

  void _saveSplit() {
    final splits = <Map<String, dynamic>>[];
    for (final row in _splitRows) {
      final name = (row['nameController'] as TextEditingController).text.trim();
      final amt = double.tryParse((row['amountController'] as TextEditingController).text) ?? 0.0;
      if (name.isNotEmpty && amt > 0) {
        splits.add({'contactName': name, 'amount': amt, 'note': _noteController.text.trim()});
      }
    }

    if (splits.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter at least one valid contact and share amount')),
      );
      return;
    }

    if (_totalSplitAmount > widget.transaction.amount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Total split amount cannot exceed transaction amount')),
      );
      return;
    }

    PeerDebtState().splitTransaction(
      transactionId: widget.transaction.id,
      merchantName: widget.transaction.merchantName,
      currency: widget.transaction.currency,
      splits: splits,
    );

    Navigator.of(context).pop();
    widget.onCompleted?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Split transaction among ${splits.length} contacts! Your share: ${widget.transaction.currency} ${_personalShare.toStringAsFixed(2)}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Split / Lent Tracking',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long, color: Colors.blueGrey),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.transaction.merchantName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Total: ${widget.transaction.currency} ${widget.transaction.amount.toStringAsFixed(2)}',
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('100% Lent'), icon: Icon(Icons.volunteer_activism)),
                  ButtonSegment(value: 1, label: Text('Split Bill'), icon: Icon(Icons.call_split)),
                ],
                selected: {_selectedMode},
                onSelectionChanged: (set) => setState(() => _selectedMode = set.first),
              ),
              const SizedBox(height: 20),
              if (_selectedMode == 0) ...[
                const Text('Contact who owes you:'),
                const SizedBox(height: 6),
                TextField(
                  controller: _contactController,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Rahul Sharma',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '💡 Marking as 100% lent will offset your personal expense to ₹0.00 and add ₹${widget.transaction.amount.toStringAsFixed(2)} to their debt ledger.',
                  style: const TextStyle(fontSize: 12, color: Colors.indigo),
                ),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Borrower Shares:', style: TextStyle(fontWeight: FontWeight.bold)),
                    TextButton.icon(
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add Person'),
                      onPressed: () {
                        setState(() {
                          _splitRows.add({
                            'nameController': TextEditingController(),
                            'amountController': TextEditingController(),
                          });
                        });
                      },
                    ),
                  ],
                ),
                ..._splitRows.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final row = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: row['nameController'] as TextEditingController,
                            decoration: InputDecoration(
                              hintText: 'Contact #${idx + 1}',
                              isDense: true,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: row['amountController'] as TextEditingController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              prefixText: '${widget.transaction.currency} ',
                              hintText: '0.00',
                              isDense: true,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        if (_splitRows.length > 1)
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                            onPressed: () {
                              setState(() => _splitRows.removeAt(idx));
                            },
                          ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Your Personal Net Share:'),
                      Text(
                        '${widget.transaction.currency} ${_personalShare.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _selectedMode == 0 ? _save100PercentLent : _saveSplit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    child: Text(_selectedMode == 0 ? 'Save 100% Lent' : 'Apply Split'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

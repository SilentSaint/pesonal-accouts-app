import 'package:flutter/material.dart';
import '../services/bill_service.dart';

class BillTrackerScreen extends StatefulWidget {
  const BillTrackerScreen({super.key});

  @override
  State<BillTrackerScreen> createState() => _BillTrackerScreenState();
}

class _BillTrackerScreenState extends State<BillTrackerScreen> {
  final BillState _billState = BillState();

  @override
  void initState() {
    super.initState();
    _billState.addListener(_onStateChange);
  }

  @override
  void dispose() {
    _billState.removeListener(_onStateChange);
    super.dispose();
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  void _showAddBillDialog() {
    final cardNameController = TextEditingController();
    final totalController = TextEditingController();
    final minController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Credit Card Bill Statement'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: cardNameController,
                decoration: const InputDecoration(labelText: 'Card Name', hintText: 'e.g. HDFC Regalia'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: totalController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Total Statement Amount', prefixText: '₹ '),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: minController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Minimum Due', prefixText: '₹ '),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final card = cardNameController.text.trim();
              final total = double.tryParse(totalController.text) ?? 0.0;
              final min = double.tryParse(minController.text) ?? (total * 0.05);

              if (card.isNotEmpty && total > 0) {
                _billState.registerBill(
                  cardAccountId: 'acc-card-manual',
                  cardName: card,
                  totalAmount: total,
                  minimumDue: min,
                  statementDate: DateTime.now().subtract(const Duration(days: 15)),
                  dueDate: DateTime.now().add(const Duration(days: 15)),
                );
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Added bill statement for $card')),
                );
              }
            },
            child: const Text('Add Statement'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bills = _billState.bills;
    final pending = _billState.pendingBills;
    final totalPending = _billState.totalPendingBillAmount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Credit Card Bills & Due Dates'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Bill',
            onPressed: _showAddBillDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary Hero
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF991B1B), Color(0xFFB91C1C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text('Total Outstanding Bills', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text('₹${totalPending.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Container(width: 1, height: 40, color: Colors.white24),
                  Column(
                    children: [
                      const Text('Pending Statements', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text('${pending.length}', style: const TextStyle(color: Colors.amberAccent, fontSize: 22, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Credit Card Statements (${bills.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (bills.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Text('No credit card bill statements recorded.'),
                ),
              )
            else
              ...bills.map((bill) {
                final isPaid = bill.isPaid;
                final days = bill.daysUntilDue;
                final dueText = isPaid
                    ? 'Paid'
                    : (days < 0 ? 'Overdue by ${days.abs()} days' : 'Due in $days days');

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(bill.cardName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Chip(
                              label: Text(
                                dueText,
                                style: TextStyle(
                                  color: isPaid ? Colors.green : (days < 3 ? Colors.red : Colors.orange.shade800),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              backgroundColor: isPaid ? Colors.green.shade50 : (days < 3 ? Colors.red.shade50 : Colors.orange.shade50),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Statement Total', style: TextStyle(color: Colors.grey, fontSize: 11)),
                                Text('₹${bill.totalAmount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Minimum Due', style: TextStyle(color: Colors.grey, fontSize: 11)),
                                Text('₹${bill.minimumDue.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigo)),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Payment Due Date', style: TextStyle(color: Colors.grey, fontSize: 11)),
                                Text(
                                  '${bill.dueDate.day}/${bill.dueDate.month}/${bill.dueDate.year}',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade800),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (!isPaid)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              ElevatedButton.icon(
                                icon: const Icon(Icons.check, size: 16),
                                label: const Text('Mark as Paid'),
                                onPressed: () {
                                  _billState.recordPayment(bill.id);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Marked bill for ${bill.cardName} as Paid!')),
                                  );
                                },
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddBillDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Statement'),
      ),
    );
  }
}

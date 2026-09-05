import 'package:flutter/material.dart';
import '../domain/peer_debt_entry.dart';
import '../services/peer_debt_service.dart';

class PeerDebtScreen extends StatefulWidget {
  const PeerDebtScreen({super.key});

  @override
  State<PeerDebtScreen> createState() => _PeerDebtScreenState();
}

class _PeerDebtScreenState extends State<PeerDebtScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final PeerDebtState _state = PeerDebtState();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _state.addListener(_onStateChange);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _state.removeListener(_onStateChange);
    super.dispose();
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  void _showAddDebtDialog() {
    final contactController = TextEditingController();
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    bool isLent = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Record Peer Debt / Loan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('I Lent (+)', style: TextStyle(fontSize: 12))),
                    ButtonSegment(value: false, label: Text('I Borrowed (-)', style: TextStyle(fontSize: 12))),
                  ],
                  selected: {isLent},
                  onSelectionChanged: (val) => setDialogState(() => isLent = val.first),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: contactController,
                  decoration: const InputDecoration(
                    labelText: 'Contact Name',
                    hintText: 'e.g. Alex',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(
                    labelText: 'Description / Note (Optional)',
                    prefixIcon: Icon(Icons.note),
                    border: OutlineInputBorder(),
                  ),
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
                final contact = contactController.text.trim();
                final amt = double.tryParse(amountController.text) ?? 0.0;
                if (contact.isNotEmpty && amt > 0) {
                  _state.recordDirectDebt(
                    contactName: contact,
                    amount: amt,
                    isLent: isLent,
                    description: noteController.text.trim(),
                  );
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Recorded ${isLent ? 'lent' : 'borrowed'} ₹$amt for $contact')),
                  );
                }
              },
              child: const Text('Record'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettleDialog(PeerDebtEntry debt) {
    final amountController = TextEditingController(text: debt.remainingAmount.toStringAsFixed(2));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Settle with ${debt.contactName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Original: ₹${debt.amount.toStringAsFixed(2)}'),
            Text('Remaining: ₹${debt.remainingAmount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Settlement Amount',
                prefixText: '₹ ',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final amt = double.tryParse(amountController.text) ?? debt.remainingAmount;
              _state.settleDebt(debt.id, amt);
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Settled ₹$amt with ${debt.contactName}')),
              );
            },
            child: const Text('Confirm Settle'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summaries = _state.contactSummaries;
    final active = _state.activeDebts;
    final settled = _state.settledDebts;

    double totalLent = 0.0;
    double totalBorrowed = 0.0;
    for (final d in active) {
      if (d.isLent) {
        totalLent += d.remainingAmount;
      } else {
        totalBorrowed += d.remainingAmount;
      }
    }
    final netBalance = totalLent - totalBorrowed;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Peer Debt Ledger'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Record Debt / Loan',
            onPressed: _showAddDebtDialog,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Contacts (${summaries.length})'),
            Tab(text: 'Active (${active.length})'),
            Tab(text: 'Settled (${settled.length})'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Hero Summary Card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.indigo.shade800, Colors.indigo.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.indigo.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryCol('You Lent', '₹${totalLent.toStringAsFixed(0)}', Colors.greenAccent),
                Container(width: 1, height: 40, color: Colors.white24),
                _buildSummaryCol('You Owe', '₹${totalBorrowed.toStringAsFixed(0)}', Colors.orangeAccent),
                Container(width: 1, height: 40, color: Colors.white24),
                _buildSummaryCol(
                  'Net Balance',
                  '${netBalance >= 0 ? '+' : ''}₹${netBalance.toStringAsFixed(0)}',
                  netBalance >= 0 ? Colors.greenAccent : Colors.orangeAccent,
                ),
              ],
            ),
          ),
          // Tab views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // 1. By Contact
                summaries.isEmpty
                    ? const Center(child: Text('No active peer debt records.'))
                    : ListView.builder(
                        itemCount: summaries.length,
                        itemBuilder: (context, index) {
                          final s = summaries[index];
                          final isPositive = s.netBalance >= 0;
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isPositive ? Colors.green.shade100 : Colors.orange.shade100,
                                child: Icon(
                                  isPositive ? Icons.arrow_downward : Icons.arrow_upward,
                                  color: isPositive ? Colors.green.shade800 : Colors.orange.shade800,
                                ),
                              ),
                              title: Text(s.contactName, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('${s.activeDebtCount} active items • Lent: ₹${s.totalLent.toStringAsFixed(0)} | Borrowed: ₹${s.totalBorrowed.toStringAsFixed(0)}'),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${isPositive ? '+' : ''}₹${s.netBalance.abs().toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: isPositive ? Colors.green.shade700 : Colors.orange.shade800,
                                    ),
                                  ),
                                  Text(
                                    isPositive ? 'Owes you' : 'You owe',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                // 2. Active Debts
                active.isEmpty
                    ? const Center(child: Text('All settled! No open debts.'))
                    : ListView.builder(
                        itemCount: active.length,
                        itemBuilder: (context, index) {
                          final debt = active[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            child: ListTile(
                              leading: Icon(
                                debt.isLent ? Icons.call_made : Icons.call_received,
                                color: debt.isLent ? Colors.green : Colors.orange,
                              ),
                              title: Text('${debt.contactName} (${debt.isLent ? 'Lent' : 'Borrowed'})'),
                              subtitle: Text('${debt.description.isNotEmpty ? debt.description : 'Direct entry'}\nRemaining: ₹${debt.remainingAmount.toStringAsFixed(2)}'),
                              isThreeLine: true,
                              trailing: ElevatedButton(
                                onPressed: () => _showSettleDialog(debt),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                ),
                                child: const Text('Settle'),
                              ),
                            ),
                          );
                        },
                      ),
                // 3. Settled Debts
                settled.isEmpty
                    ? const Center(child: Text('No settled debts yet.'))
                    : ListView.builder(
                        itemCount: settled.length,
                        itemBuilder: (context, index) {
                          final debt = settled[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            child: ListTile(
                              leading: const Icon(Icons.check_circle, color: Colors.green),
                              title: Text(debt.contactName),
                              subtitle: Text('${debt.description}\nAmount: ₹${debt.amount.toStringAsFixed(2)}'),
                              trailing: const Chip(
                                label: Text('Settled', style: TextStyle(color: Colors.green, fontSize: 11)),
                                backgroundColor: Color(0xFFE8F5E9),
                              ),
                            ),
                          );
                        },
                      ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDebtDialog,
        icon: const Icon(Icons.add),
        label: const Text('Record Debt'),
      ),
    );
  }

  Widget _buildSummaryCol(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }
}

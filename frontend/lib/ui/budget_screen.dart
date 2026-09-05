import 'package:flutter/material.dart';
import '../domain/category_budget.dart';
import '../services/budget_service.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  final BudgetState _budgetState = BudgetState();
  final String _selectedMonth = '2026-08';

  @override
  void initState() {
    super.initState();
    _budgetState.addListener(_onStateChange);
  }

  @override
  void dispose() {
    _budgetState.removeListener(_onStateChange);
    super.dispose();
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  void _showSetBudgetDialog([CategoryBudgetItem? existing]) {
    final catNameController = TextEditingController(text: existing?.categoryName ?? '');
    final catIdController = TextEditingController(text: existing?.categoryId ?? '');
    final limitController = TextEditingController(text: existing != null ? existing.limitAmount.toStringAsFixed(0) : '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Create Category Budget' : 'Edit Budget: ${existing.categoryName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (existing == null) ...[
              TextField(
                controller: catNameController,
                decoration: const InputDecoration(labelText: 'Category Name', hintText: 'e.g. Fuel & Travel'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: catIdController,
                decoration: const InputDecoration(labelText: 'Category Code', hintText: 'e.g. CAT_TRAVEL'),
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: limitController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monthly Limit Amount', prefixText: '₹ '),
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
              final name = existing?.categoryName ?? catNameController.text.trim();
              final id = existing?.categoryId ?? (catIdController.text.trim().isNotEmpty ? catIdController.text.trim() : name.toUpperCase().replaceAll(' ', '_'));
              final limit = double.tryParse(limitController.text) ?? 0.0;

              if (name.isNotEmpty && id.isNotEmpty && limit > 0) {
                _budgetState.setBudget(
                  categoryId: id,
                  categoryName: name,
                  yearMonth: _selectedMonth,
                  limitAmount: limit,
                );
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Budget saved for $name')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final budgets = _budgetState.getBudgetsForMonth(_selectedMonth);
    double totalLimit = 0.0;
    double totalSpent = 0.0;
    for (final b in budgets) {
      totalLimit += b.limitAmount;
      totalSpent += b.currentSpend;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Monthly Budgets & Alerts', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            tooltip: 'Add Budget',
            onPressed: () => _showSetBudgetDialog(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Month Selector & Hero Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF312E81), Color(0xFF4338CA)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Budget Cycle', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_selectedMonth, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          const Text('Total Budget', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text('₹${totalLimit.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Container(width: 1, height: 36, color: Colors.white24),
                      Column(
                        children: [
                          const Text('Total Spent', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text('₹${totalSpent.toStringAsFixed(0)}', style: TextStyle(color: totalSpent > totalLimit ? Colors.redAccent : Colors.greenAccent, fontSize: 20, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Category Limits & Real-Time Alerts',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            if (budgets.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Text('No budgets configured for this month.', style: TextStyle(color: Colors.white54)),
                ),
              )
            else
              ...budgets.map((b) {
                final pct = b.spendPercentage.toStringAsFixed(1);
                Color barColor = const Color(0xFF22C55E); // Green
                if (b.isThreshold100Reached) {
                  barColor = const Color(0xFFEF4444); // Red
                } else if (b.isThreshold80Reached) {
                  barColor = const Color(0xFFF59E0B); // Amber
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            b.categoryName,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Row(
                            children: [
                              Text(
                                '₹${b.currentSpend.toStringAsFixed(0)} / ₹${b.limitAmount.toStringAsFixed(0)}',
                                style: TextStyle(color: barColor, fontWeight: FontWeight.bold),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit, size: 16, color: Colors.white54),
                                onPressed: () => _showSetBudgetDialog(b),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: b.progressValue,
                          backgroundColor: const Color(0xFF334155),
                          valueColor: AlwaysStoppedAnimation<Color>(barColor),
                          minHeight: 10,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (b.isThreshold100Reached)
                            const Text(
                              '🚨 Critical: 100% budget limit exceeded!',
                              style: TextStyle(color: Color(0xFFF87171), fontSize: 12, fontWeight: FontWeight.bold),
                            )
                          else if (b.isThreshold80Reached)
                            const Text(
                              '⚠️ Warning: 80% threshold reached!',
                              style: TextStyle(color: Color(0xFFFBBF24), fontSize: 12, fontWeight: FontWeight.bold),
                            )
                          else
                            Text(
                              'Remaining: ₹${b.remainingBudget.toStringAsFixed(0)}',
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                            ),
                          Text(
                            '$pct%',
                            style: TextStyle(color: barColor, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF6366F1),
        onPressed: () => _showSetBudgetDialog(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

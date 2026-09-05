import 'package:flutter/material.dart';
import '../services/card_emi_service.dart';

class CardEmiScreen extends StatefulWidget {
  const CardEmiScreen({super.key});

  @override
  State<CardEmiScreen> createState() => _CardEmiScreenState();
}

class _CardEmiScreenState extends State<CardEmiScreen> {
  final CardEmiState _emiState = CardEmiState();

  @override
  void initState() {
    super.initState();
    _emiState.addListener(_onStateChange);
  }

  @override
  void dispose() {
    _emiState.removeListener(_onStateChange);
    super.dispose();
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  void _showAddEmiDialog() {
    final merchantController = TextEditingController();
    final cardController = TextEditingController();
    final amountController = TextEditingController();
    final installmentController = TextEditingController();
    final rateController = TextEditingController(text: '14.0');
    final tenureController = TextEditingController(text: '6');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Convert Transaction to Card EMI'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: merchantController,
                decoration: const InputDecoration(labelText: 'Merchant / Item', hintText: 'e.g. Amazon India'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: cardController,
                decoration: const InputDecoration(labelText: 'Credit Card', hintText: 'e.g. SBI Card'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Total Transaction Amount', prefixText: '₹ '),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: installmentController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Monthly EMI Amount', prefixText: '₹ '),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: rateController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Rate %', suffixText: '%'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: tenureController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Tenure (Months)'),
                    ),
                  ),
                ],
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
              final merchant = merchantController.text.trim();
              final card = cardController.text.trim();
              final amount = double.tryParse(amountController.text) ?? 0.0;
              final emi = double.tryParse(installmentController.text) ?? 0.0;
              final rate = double.tryParse(rateController.text) ?? 0.0;
              final tenure = int.tryParse(tenureController.text) ?? 6;

              if (merchant.isNotEmpty && amount > 0 && emi > 0) {
                _emiState.convertToEmi(
                  cardAccountId: 'acc-card-manual',
                  cardName: card,
                  merchantName: merchant,
                  totalAmount: amount,
                  tenureMonths: tenure,
                  interestRatePercent: rate,
                  monthlyInstallment: emi,
                  nextDueDate: DateTime.now().add(const Duration(days: 25)),
                );
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Created EMI plan for $merchant')),
                );
              }
            },
            child: const Text('Convert'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plans = _emiState.plans;
    final activePlans = _emiState.activePlans;
    final totalCommitted = _emiState.totalMonthlyCommittedEmi;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Credit Card EMI Schedules'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Card EMI',
            onPressed: _showAddEmiDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF065F46), Color(0xFF047857)],
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
                      const Text('Committed Monthly EMI', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text('₹${totalCommitted.toStringAsFixed(0)}', style: const TextStyle(color: Colors.greenAccent, fontSize: 22, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Container(width: 1, height: 40, color: Colors.white24),
                  Column(
                    children: [
                      const Text('Active Plans', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text('${activePlans.length}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Active Installment Schedules (${activePlans.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (plans.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Text('No active card EMI plans.'),
                ),
              )
            else
              ...plans.map((plan) {
                final pct = (plan.progressPercentage * 100).toStringAsFixed(0);
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
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(plan.merchantName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  Text('${plan.cardName} • ${plan.interestRatePercent}% p.a.', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                ],
                              ),
                            ),
                            Chip(
                              label: Text(
                                plan.isCompleted ? 'Completed' : 'Active',
                                style: TextStyle(
                                  color: plan.isCompleted ? Colors.green : Colors.teal,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              backgroundColor: plan.isCompleted ? Colors.green.shade50 : Colors.teal.shade50,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Progress: $pct%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            Text(
                              '${plan.completedInstallments} / ${plan.totalTenureMonths} installments (${plan.remainingInstallments} remaining)',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: plan.progressPercentage,
                            minHeight: 8,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(plan.isCompleted ? Colors.green : Colors.teal),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Installment Amount', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                Text('₹${plan.monthlyInstallment.toStringAsFixed(0)}/mo', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Next Billing Due', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                Text(
                                  '${plan.nextDueDate.day}/${plan.nextDueDate.month}/${plan.nextDueDate.year}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.teal),
                                ),
                              ],
                            ),
                            if (!plan.isCompleted)
                              OutlinedButton.icon(
                                icon: const Icon(Icons.check, size: 16),
                                label: const Text('Mark Paid'),
                                onPressed: () {
                                  _emiState.recordInstallmentPaid(plan.id);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Recorded installment for ${plan.merchantName}')),
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
        onPressed: _showAddEmiDialog,
        icon: const Icon(Icons.add),
        label: const Text('Convert EMI'),
      ),
    );
  }
}

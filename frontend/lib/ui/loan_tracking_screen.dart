import 'package:flutter/material.dart';
import '../services/loan_service.dart';

class LoanTrackingScreen extends StatefulWidget {
  const LoanTrackingScreen({super.key});

  @override
  State<LoanTrackingScreen> createState() => _LoanTrackingScreenState();
}

class _LoanTrackingScreenState extends State<LoanTrackingScreen> {
  final LoanState _loanState = LoanState();

  @override
  void initState() {
    super.initState();
    _loanState.addListener(_onStateChange);
  }

  @override
  void dispose() {
    _loanState.removeListener(_onStateChange);
    super.dispose();
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  void _showAddLoanDialog() {
    final loanNameController = TextEditingController();
    final lenderController = TextEditingController();
    final principalController = TextEditingController();
    final emiController = TextEditingController();
    final rateController = TextEditingController(text: '8.5');
    final tenureController = TextEditingController(text: '60');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Register Loan Account'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: loanNameController,
                decoration: const InputDecoration(labelText: 'Loan Name', hintText: 'e.g. Home Loan'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: lenderController,
                decoration: const InputDecoration(labelText: 'Lender / Bank', hintText: 'e.g. HDFC Bank'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: principalController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Total Principal Amount', prefixText: '₹ '),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: emiController,
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
                      decoration: const InputDecoration(labelText: 'Interest Rate %', suffixText: '%'),
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
              final name = loanNameController.text.trim();
              final lender = lenderController.text.trim();
              final principal = double.tryParse(principalController.text) ?? 0.0;
              final emi = double.tryParse(emiController.text) ?? 0.0;
              final rate = double.tryParse(rateController.text) ?? 0.0;
              final tenure = int.tryParse(tenureController.text) ?? 12;

              if (name.isNotEmpty && lender.isNotEmpty && principal > 0 && emi > 0) {
                _loanState.registerLoan(
                  loanName: name,
                  lenderName: lender,
                  principalAmount: principal,
                  emiAmount: emi,
                  interestRatePercent: rate,
                  totalInstallments: tenure,
                  nextDueDate: DateTime.now().add(const Duration(days: 30)),
                );
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Registered loan: $name')),
                );
              }
            },
            child: const Text('Register'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loans = _loanState.loans;
    final activeLoans = _loanState.activeLoans;

    double totalMonthlyEmi = 0.0;
    double totalOutstanding = 0.0;
    for (final l in activeLoans) {
      totalMonthlyEmi += l.emiAmount;
      totalOutstanding += l.remainingPrincipal;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Loan & EMI Tracking'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Register Loan',
            onPressed: _showAddLoanDialog,
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
                gradient: LinearGradient(
                  colors: [Colors.deepPurple.shade900, Colors.deepPurple.shade700],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          const Text('Total Monthly EMI', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text('₹${totalMonthlyEmi.toStringAsFixed(0)}', style: const TextStyle(color: Colors.amberAccent, fontSize: 20, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Container(width: 1, height: 40, color: Colors.white24),
                      Column(
                        children: [
                          const Text('Total Outstanding', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text('₹${(totalOutstanding / 100000).toStringAsFixed(2)} Lakh', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Active Loans (${activeLoans.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (loans.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Text('No loans registered.'),
                ),
              )
            else
              ...loans.map((loan) {
                final pct = (loan.progressPercentage * 100).toStringAsFixed(1);
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
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(loan.loanName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                Text('${loan.lenderName} • ${loan.interestRatePercent}% p.a.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                              ],
                            ),
                            Chip(
                              label: Text(
                                loan.isClosed ? 'Closed' : 'Active',
                                style: TextStyle(color: loan.isClosed ? Colors.green : Colors.deepPurple, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              backgroundColor: loan.isClosed ? Colors.green.shade50 : Colors.deepPurple.shade50,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Progress: $pct%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            Text(
                              '${loan.completedInstallments} of ${loan.totalInstallments} paid (${loan.remainingInstallments} left)',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: loan.progressPercentage,
                            minHeight: 8,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(loan.isClosed ? Colors.green : Colors.deepPurple),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Monthly EMI', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                Text('₹${loan.emiAmount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Next Due Date', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                Text(
                                  '${loan.nextDueDate.day}/${loan.nextDueDate.month}/${loan.nextDueDate.year}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigo),
                                ),
                              ],
                            ),
                            if (!loan.isClosed)
                              OutlinedButton.icon(
                                icon: const Icon(Icons.check, size: 16),
                                label: const Text('Record EMI'),
                                onPressed: () {
                                  _loanState.recordEmiPayment(loan.id);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Recorded EMI payment for ${loan.loanName}')),
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
        onPressed: _showAddLoanDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Loan'),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/financial_account.dart';
import '../domain/transaction_item.dart';
import '../services/entity_service.dart';
import 'theme/app_theme.dart';

class TransactionReviewModal extends StatefulWidget {
  final List<TransactionItem> pendingTransactions;
  final List<TransactionItem>? existingTransactions;
  final List<FinancialAccount>? existingAccounts;
  final FutureOr<bool> Function(TransactionItem item, String category)
      onConfirm;
  final FutureOr<void> Function(
      TransactionItem targetItem, TransactionItem duplicateItem) onMerge;
  final Function(TransactionItem item) onDismiss;
  final Function(TransactionItem item)? onMarkPromotional;
  final Function(FinancialAccount newAccount)? onCreateLoanAccount;
  final VoidCallback? onPurgeInvalid;
  final String? Function()? confirmationErrorMessage;

  const TransactionReviewModal({
    super.key,
    required this.pendingTransactions,
    this.existingTransactions,
    this.existingAccounts,
    required this.onConfirm,
    required this.onMerge,
    required this.onDismiss,
    this.onMarkPromotional,
    this.onCreateLoanAccount,
    this.onPurgeInvalid,
    this.confirmationErrorMessage,
  });

  @override
  State<TransactionReviewModal> createState() => _TransactionReviewModalState();
}

class _TransactionReviewModalState extends State<TransactionReviewModal> {
  final Map<String, String> _selectedCategories = {};
  final Map<String, String> _selectedSubCategories = {};
  final Map<String, String> _selectedEntities = {};
  final Map<String, double> _overrideAmounts = {};
  String? _confirmingTransactionId;
  String? _confirmationErrorTransactionId;
  String? _confirmationErrorMessage;

  static const List<String> _categories = [
    'Income',
    'Food & Dining',
    'Groceries',
    'Shopping',
    'Transport & Fuel',
    'Bills & Utilities',
    'Investments',
    'Loans & Debt',
    'Healthcare',
    'Entertainment',
    'Personal Transfers',
    'Self Transfer',
    'General Expenses',
    'Not Applicable / Exclude',
  ];

  final Map<String, List<String>> _subCategories = {
    'Self Transfer': [
      'Account to Account Transfer',
      'Self UPI Transfer',
      'Savings to Investment',
      'Credit Card Bill Payment',
      'Wallet Top-up',
    ],
    'Loans & Debt': [
      'Personal Loan EMI',
      'Home Loan EMI',
      'Car Loan EMI',
      'Education Loan EMI',
      'Consumer Loan EMI',
      'General Loan EMI',
    ],
    'Income': [
      'Salary',
      'Bonus & Incentives',
      'Freelance & Consulting',
      'Reimbursements',
      'Dividends & Interest',
      'Rental Income',
      'Refunds',
    ],
    'Food & Dining': [
      'Tea & Snacks',
      'Restaurants & Cafes',
      'Coffee & Bakeries',
      'Street Food',
      'Online Delivery (Swiggy/Zomato)',
      'Fast Food & Takeaway',
      'Bar & Pub',
    ],
    'Groceries': [
      'Supermarket',
      'Fruits & Vegetables',
      'Dairy & Eggs',
      'Local Kirana Store',
      'Meat & Seafood',
    ],
    'Transport & Fuel': [
      'Fuel & Petrol',
      'Cabs & Rides (Uber/Ola)',
      'Metro & Rail',
      'Bus & Transit',
      'FASTag & Tolls',
      'Parking',
      'Auto & Bike Repair',
    ],
    'Shopping': [
      'Clothing & Apparel',
      'Electronics & Gadgets',
      'Home & Kitchen',
      'Online Shopping (Amazon/Flipkart)',
      'Personal Care & Cosmetics',
      'Books & Stationery',
    ],
    'Bills & Utilities': [
      'Credit Card Bill',
      'Electricity Bill',
      'Mobile Recharge & Postpaid',
      'Broadband / Wi-Fi',
      'Water Bill',
      'House Rent',
      'Maid & Cook Wages',
      'LPG Cylinder',
      'Society Maintenance',
    ],
    'Investments': [
      'Recurring Deposit (RD)',
      'Mutual Funds & SIP',
      'Stocks & Demat',
      'Fixed Deposit',
      'Gold & Silver',
      'Provident Fund / NPS',
      'Crypto',
    ],
    'Healthcare': [
      'Doctor & Clinic Visit',
      'Medicines & Pharmacy',
      'Lab Diagnostics & Scans',
      'Health Insurance',
      'Dental & Optical',
    ],
    'Entertainment': [
      'Movies & Theatres',
      'Streaming OTT (Netflix/Prime)',
      'Music & Gaming',
      'Events & Concerts',
      'Hobbies & Outings',
    ],
    'Personal Transfers': [
      'Friends & Family',
      'Domestic Staff',
      'Rent Transfer',
      'Reimbursements',
      'Loans Repaid/Given',
    ],
    'General Expenses': [
      'Miscellaneous',
      'Cash Withdrawal (ATM)',
      'Bank Charges & Fees',
      'Charity & Donations',
    ],
  };

  @override
  void initState() {
    super.initState();
    _loadCustomSubCategories();
    final entityService = EntityService();

    for (int idx = 0; idx < widget.pendingTransactions.length; idx++) {
      final t = widget.pendingTransactions[idx];
      final selfPair = _findSelfTransferPair(t, idx);
      final displayMerchant = _getDisplayMerchant(t);
      final displayVpa = _getDisplayVpa(t);
      final displayAccount = _getDisplayAccountMask(t);

      final matched = entityService.matchEntity(
        upiId: displayVpa,
        accountMask: displayAccount,
        rawName: displayMerchant,
      );

      String cat = matched?.defaultCategory ??
          ((t.categoryId != null &&
                  _categories.contains(t.categoryId) &&
                  t.categoryId != 'General Expenses')
              ? t.categoryId!
              : '');

      if (selfPair != null ||
          displayMerchant == 'Self Transfer' ||
          t.isTransfer ||
          t.categoryId == 'Self Transfer') {
        cat = 'Self Transfer';
      } else if (cat.isEmpty) {
        final text =
            '${t.merchantName} ${t.rawSnippet ?? ''} ${t.referenceNumber ?? ''}'
                .toLowerCase();
        if (text.contains('fastag')) {
          cat = 'Transport & Fuel';
        } else if (text.contains('cred.rent') ||
            (text.contains('rent') && text.contains('dreamplug'))) {
          cat = 'Bills & Utilities';
        } else if (text.contains('added to emi') ||
            text.contains('towards emi') ||
            text.contains('loan account') ||
            text.contains(' emi ')) {
          cat = 'Loans & Debt';
        } else if (text.contains('salary') ||
            text.contains('received a credit')) {
          cat = 'Income';
        } else if (text.contains('recurring deposit') ||
            text.contains(' rd ')) {
          cat = 'Investments';
        } else if (t.categoryId != null && _categories.contains(t.categoryId)) {
          cat = t.categoryId!;
        } else {
          cat = 'General Expenses';
        }
      }

      _selectedCategories[t.id] = cat;
      _selectedEntities[t.id] = (cat == 'Self Transfer')
          ? 'Self Transfer'
          : (matched != null ? matched.name : displayMerchant);

      final availableSubs = _subCategories[cat] ?? [];
      final fullTextLower =
          '${t.merchantName} ${t.rawSnippet ?? ''} ${t.referenceNumber ?? ''}'
              .toLowerCase();
      if (cat == 'Self Transfer') {
        _selectedSubCategories[t.id] = 'Account to Account Transfer';
      } else if (matched?.defaultSubCategory != null &&
          matched!.defaultSubCategory!.isNotEmpty) {
        _selectedSubCategories[t.id] = matched.defaultSubCategory!;
        if (!availableSubs.contains(matched.defaultSubCategory!)) {
          availableSubs.insert(0, matched.defaultSubCategory!);
        }
      } else if (t.subCategory != null && t.subCategory!.isNotEmpty) {
        _selectedSubCategories[t.id] = t.subCategory!;
        if (!availableSubs.contains(t.subCategory!)) {
          availableSubs.insert(0, t.subCategory!);
        }
      } else if (cat == 'Transport & Fuel' &&
          fullTextLower.contains('fastag')) {
        _selectedSubCategories[t.id] = 'FASTag & Tolls';
      } else if (cat == 'Bills & Utilities' && fullTextLower.contains('rent')) {
        _selectedSubCategories[t.id] = 'House Rent';
      } else {
        _selectedSubCategories[t.id] =
            availableSubs.isNotEmpty ? availableSubs.first : '';
      }
    }
  }

  Future<void> _loadCustomSubCategories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('saved_custom_subcategories');
      if (raw != null) {
        final Map<String, dynamic> decoded = jsonDecode(raw);
        decoded.forEach((k, v) {
          if (v is List) {
            final list = _subCategories.putIfAbsent(k, () => []);
            for (final item in v) {
              final str = item.toString().trim();
              if (str.isNotEmpty && !list.contains(str)) {
                list.add(str);
              }
            }
          }
        });
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _saveCustomSubCategories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'saved_custom_subcategories', jsonEncode(_subCategories));
    } catch (_) {}
  }

  Future<void> _promptEditAmount(
      BuildContext context, TransactionItem txn) async {
    final currentAmt = _overrideAmounts[txn.id] ?? txn.amount;
    final controller = TextEditingController(
      text: currentAmt > 0 ? currentAmt.toStringAsFixed(2) : '',
    );
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.edit_note, color: Color(0xFF38BDF8), size: 22),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Set / Update Bill Amount',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the total amount due for ${txn.merchantName}. This allows accounting for card statements or cashback/fee adjustments.',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('review-amount-input'),
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                prefixText: '₹ ',
                prefixStyle: const TextStyle(
                    color: Color(0xFF38BDF8),
                    fontSize: 15,
                    fontWeight: FontWeight.bold),
                labelText: 'Total Bill Amount (INR)',
                hintText: 'e.g. 7485.00',
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                labelStyle:
                    const TextStyle(color: Color(0xFF38BDF8), fontSize: 13),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              final raw = controller.text.trim().replaceAll(',', '');
              final val = double.tryParse(raw);
              if (val != null && val >= 0) {
                Navigator.of(ctx).pop(val);
              }
            },
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Save Amount'),
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() {
        _overrideAmounts[txn.id] = result;
      });
    }
  }

  bool _isLoanEmiTransaction(TransactionItem txn) {
    final text = '${txn.merchantName} ${txn.rawSnippet ?? ''}'.toLowerCase();
    return text.contains('added to emi') ||
        text.contains('towards emi') ||
        text.contains('loan account') ||
        text.contains('loan a/c') ||
        text.contains(' emi ');
  }

  String? _extractLoanAccountMask(TransactionItem txn) {
    final text = '${txn.merchantName} ${txn.rawSnippet ?? ''}';
    final emiMatch = RegExp(
            r'(?:added\s+to\s+EMI|towards\s+EMI|\bEMI)\s*([xX*]*\d{4,16})',
            caseSensitive: false)
        .firstMatch(text);
    if (emiMatch != null && emiMatch.group(1) != null) {
      final g = emiMatch.group(1)!;
      return '•••• ${g.substring(g.length >= 4 ? g.length - 4 : 0)}';
    }
    return null;
  }

  Future<void> _showLoanAccountSetupDialog(
      BuildContext context, TransactionItem txn) async {
    final text = '${txn.merchantName} ${txn.rawSnippet ?? ''}';
    final emiMatch = RegExp(
            r'(?:added\s+to\s+EMI|towards\s+EMI|\bEMI)\s*([xX*]*\d{4,16})',
            caseSensitive: false)
        .firstMatch(text);
    final loanNumber = emiMatch?.group(1) ?? '0733';
    final last4 = loanNumber
        .substring(loanNumber.length >= 4 ? loanNumber.length - 4 : 0);
    final bankMatch = RegExp(
            r'\b(HDFC|ICICI|SBI|AXIS|KOTAK|RBL|YES|IDFC|BOB|PNB|CANARA|INDUSIND)\s+Bank',
            caseSensitive: false)
        .firstMatch(text);
    final lender = bankMatch != null ? '${bankMatch.group(1)} Bank' : 'Bank';

    final nameController =
        TextEditingController(text: '$lender Loan (•••• $last4)');
    final lenderController = TextEditingController(text: lender);
    final emiController = TextEditingController(
        text: txn.amount > 0 ? txn.amount.toStringAsFixed(2) : '');
    final originalPrincipalController = TextEditingController();
    final remainingPrincipalController = TextEditingController();
    final rateController = TextEditingController();
    final totalMonthsController = TextEditingController();
    final completedMonthsController = TextEditingController(text: '1');

    final result = await showDialog<FinancialAccount>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final totalM = int.tryParse(totalMonthsController.text.trim());
          final paidM =
              int.tryParse(completedMonthsController.text.trim()) ?? 1;
          final remainingM = (totalM != null && totalM > 0)
              ? (totalM - paidM).clamp(0, 999)
              : null;

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1B2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFF8B5CF6), width: 1.2),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0x338B5CF6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.account_balance,
                      color: Color(0xFFA78BFA), size: 22),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Setup Loan Account',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Track original loan, remaining balance & tenure',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0x228B5CF6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0x448B5CF6)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome,
                            color: Color(0xFFA78BFA), size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Detected EMI of ₹${txn.amount.toStringAsFixed(2)} towards Loan A/C •••• $last4',
                            style: const TextStyle(
                                color: Color(0xFFDDD6FE),
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Loan Account Name',
                      labelStyle:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: lenderController,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Lender / Bank',
                            labelStyle: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: emiController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Monthly EMI (₹)',
                            labelStyle: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Principal & Outstanding Balance',
                      style: TextStyle(
                          color: Color(0xFFA78BFA),
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: originalPrincipalController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Original Loan (₹)',
                            hintText: 'Taken at start',
                            hintStyle: const TextStyle(
                                color: Colors.white24, fontSize: 10),
                            labelStyle: const TextStyle(
                                color: Colors.white70, fontSize: 11),
                            helperText: 'e.g. ₹5,00,000 borrowed',
                            helperStyle: const TextStyle(
                                color: Colors.white38, fontSize: 9),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: remainingPrincipalController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Remaining Principal (₹)',
                            hintText: 'Balance left',
                            hintStyle: const TextStyle(
                                color: Colors.white24, fontSize: 10),
                            labelStyle: const TextStyle(
                                color: Colors.white70, fontSize: 11),
                            helperText: 'Outstanding debt to pay',
                            helperStyle: const TextStyle(
                                color: Colors.white38, fontSize: 9),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Tenure & Installments',
                      style: TextStyle(
                          color: Color(0xFFA78BFA),
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: totalMonthsController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          onChanged: (_) => setDialogState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Total Tenure (Months)',
                            hintText: 'e.g. 36',
                            hintStyle: const TextStyle(
                                color: Colors.white24, fontSize: 10),
                            labelStyle: const TextStyle(
                                color: Colors.white70, fontSize: 11),
                            helperText: 'Full loan period',
                            helperStyle: const TextStyle(
                                color: Colors.white38, fontSize: 9),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: completedMonthsController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          onChanged: (_) => setDialogState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Months Paid So Far',
                            hintText: 'e.g. 12',
                            hintStyle: const TextStyle(
                                color: Colors.white24, fontSize: 10),
                            labelStyle: const TextStyle(
                                color: Colors.white70, fontSize: 11),
                            helperText: 'Installments completed',
                            helperStyle: const TextStyle(
                                color: Colors.white38, fontSize: 9),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (remainingM != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0x1A34D399),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0x3334D399)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline,
                              color: Color(0xFF34D399), size: 14),
                          const SizedBox(width: 6),
                          Text(
                            '$remainingM months remaining ($paidM of $totalM paid)',
                            style: const TextStyle(
                                color: Color(0xFFA7F3D0),
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: rateController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Interest Rate % (Annual)',
                      hintText: 'e.g. 10.5',
                      hintStyle:
                          const TextStyle(color: Colors.white24, fontSize: 11),
                      labelStyle:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  final emiVal = double.tryParse(
                          emiController.text.trim().replaceAll(',', '')) ??
                      txn.amount;
                  final origPrincipalVal = double.tryParse(
                      originalPrincipalController.text
                          .trim()
                          .replaceAll(',', ''));
                  final remPrincipalVal = double.tryParse(
                      remainingPrincipalController.text
                          .trim()
                          .replaceAll(',', ''));
                  final rateVal = double.tryParse(
                      rateController.text.trim().replaceAll(',', ''));
                  final totalMVal =
                      int.tryParse(totalMonthsController.text.trim());
                  final paidMVal =
                      int.tryParse(completedMonthsController.text.trim()) ?? 1;

                  final newAcc = FinancialAccount(
                    id: 'acc-loan-${DateTime.now().millisecondsSinceEpoch}',
                    name: nameController.text.trim().isNotEmpty
                        ? nameController.text.trim()
                        : '$lender Loan (•••• $last4)',
                    type: 'LOAN',
                    lastFourDigits: last4,
                    currency: 'INR',
                    currentBalance: remPrincipalVal ?? origPrincipalVal ?? 0.0,
                    emiAmount: emiVal,
                    principalAmount: origPrincipalVal ?? remPrincipalVal,
                    interestRatePercent: rateVal,
                    totalInstallments: totalMVal,
                    completedInstallments: paidMVal,
                    lenderName: lenderController.text.trim(),
                  );
                  Navigator.of(ctx).pop(newAcc);
                },
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Save Loan Account'),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      widget.onCreateLoanAccount?.call(result);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Created Loan Account: ${result.name}!'),
            backgroundColor: const Color(0xFF8B5CF6),
          ),
        );
      }
    }
  }

  Future<String?> _promptAddSubCategory(
      BuildContext context, String parentCategory) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.playlist_add,
                color: AppColors.primaryLight, size: 22),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'New Sub-Category for $parentCategory',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add a specific sub-category under "$parentCategory" (e.g. Tea & Snacks, Office Lunch, Car Wash).',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Sub-Category Name',
                hintText: 'e.g. Tea & Snacks',
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                labelStyle: const TextStyle(
                    color: AppColors.primaryLight, fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.of(ctx).pop(name);
              }
            },
            icon: const Icon(Icons.check, size: 15, color: Colors.white),
            label: const Text('Add Sub-Category',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final list = _subCategories.putIfAbsent(parentCategory, () => []);
      if (!list.contains(result)) {
        list.insert(0, result);
        await _saveCustomSubCategories();
      }
      return result;
    }
    return null;
  }

  Future<void> _promptSetCustomAlias(
    BuildContext context,
    TransactionItem txn,
    String currentAlias,
    String rawVendorName,
    String? vpa,
    String? accountMask,
  ) async {
    final isAggregator = EntityService.isPlatformAggregator(rawVendorName) ||
        EntityService.isPlatformAggregator(currentAlias);
    final hasFastagVpa = vpa != null && vpa.toLowerCase().contains('fastag');

    final initialName = hasFastagVpa &&
            (currentAlias == rawVendorName ||
                currentAlias == 'Dreamplug Service Private Limited')
        ? 'CRED (FASTag Recharge)'
        : currentAlias;
    final controller = TextEditingController(text: initialName);

    String chosenCat = _selectedCategories[txn.id] ??
        (hasFastagVpa ? 'Transport & Fuel' : 'General Expenses');
    if (hasFastagVpa && chosenCat == 'General Expenses') {
      chosenCat = 'Transport & Fuel';
    }
    String? chosenSubCat = _selectedSubCategories[txn.id] ??
        (hasFastagVpa ? 'FASTag & Tolls' : null);
    if (hasFastagVpa &&
        (chosenSubCat == null ||
            chosenSubCat.isEmpty ||
            chosenSubCat == 'Miscellaneous')) {
      chosenSubCat = 'FASTag & Tolls';
    }

    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final availableSubs = _subCategories[chosenCat] ?? [];
          if (chosenSubCat == null ||
              (!availableSubs.contains(chosenSubCat) &&
                  availableSubs.isNotEmpty)) {
            chosenSubCat =
                availableSubs.isNotEmpty ? availableSubs.first : null;
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.edit_note, color: AppColors.primaryLight, size: 24),
                SizedBox(width: 8),
                Text('Set Custom Alias & Category',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Give this vendor a custom name and default sub-category (e.g. "My Maid" › "Maid & Cook Wages" or "Tea Stall" › "Tea & Snacks").',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('Detected Vendor: ',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 11)),
                            Text(rawVendorName,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12)),
                          ],
                        ),
                        if (vpa != null && vpa.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              const Text('UPI ID: ',
                                  style: TextStyle(
                                      color: Colors.white54, fontSize: 11)),
                              Text(vpa,
                                  style: const TextStyle(
                                      color: Color(0xFF93C5FD), fontSize: 11)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (hasFastagVpa || isAggregator) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0x1A38BDF8),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0x4438BDF8)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.info_outline,
                                  size: 14, color: Color(0xFF38BDF8)),
                              SizedBox(width: 6),
                              Text('Multi-Service Platform Mapping',
                                  style: TextStyle(
                                      color: Color(0xFFBAE6FD),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isAggregator
                                ? 'Dreamplug / CRED handles multiple services (FASTag, rent, utility bills). This alias will map specifically to UPI ID ($vpa) so other CRED services remain separate.'
                                : 'Mapping is tied to UPI ID ($vpa) for accurate vendor categorization.',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 11),
                          ),
                          if (hasFastagVpa) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              children: [
                                ActionChip(
                                  backgroundColor: const Color(0xFF0284C7),
                                  label: const Text('🚗 CRED (FASTag Recharge)',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold)),
                                  onPressed: () {
                                    setDialogState(() {
                                      controller.text =
                                          'CRED (FASTag Recharge)';
                                      chosenCat = 'Transport & Fuel';
                                      chosenSubCat = 'FASTag & Tolls';
                                    });
                                  },
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  Builder(
                    builder: (ctx) {
                      final existingAliasNames = <String>{};
                      for (final ent in EntityService().entities) {
                        if (ent.name.isNotEmpty &&
                            ent.name != 'Self Transfer') {
                          existingAliasNames.add(ent.name);
                        }
                      }
                      if (widget.existingTransactions != null) {
                        for (final t in widget.existingTransactions!) {
                          if (t.merchantName.isNotEmpty &&
                              t.merchantName != 'Self Transfer' &&
                              t.merchantName != 'Bank Alert') {
                            existingAliasNames.add(t.merchantName);
                          }
                        }
                      }
                      existingAliasNames.removeWhere((n) =>
                          n.toLowerCase() == rawVendorName.toLowerCase());

                      if (existingAliasNames.isEmpty)
                        return const SizedBox(height: 14);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),
                          const Row(
                            children: [
                              Icon(Icons.storefront_outlined,
                                  size: 14, color: Color(0xFF38BDF8)),
                              SizedBox(width: 5),
                              Text('Link to an existing shop / alias:',
                                  style: TextStyle(
                                      color: Color(0xFFBAE6FD),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: existingAliasNames.take(8).map((alias) {
                              final isSelected =
                                  controller.text.toLowerCase().trim() ==
                                      alias.toLowerCase().trim();
                              return ActionChip(
                                backgroundColor: isSelected
                                    ? const Color(0xFF0284C7)
                                    : const Color(0xFF1E293B),
                                side: BorderSide(
                                    color: isSelected
                                        ? const Color(0xFF38BDF8)
                                        : const Color(0xFF334155)),
                                label: Text(
                                  alias,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : const Color(0xFFE2E8F0),
                                    fontSize: 11,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                                onPressed: () {
                                  setDialogState(() {
                                    controller.text = alias;
                                    final matched = EntityService()
                                        .entities
                                        .where((e) =>
                                            e.name.toLowerCase() ==
                                            alias.toLowerCase())
                                        .firstOrNull;
                                    if (matched?.defaultCategory != null) {
                                      chosenCat = matched!.defaultCategory!;
                                      chosenSubCat = matched.defaultSubCategory;
                                    } else {
                                      final exTxn = widget.existingTransactions
                                          ?.where((t) =>
                                              t.merchantName.toLowerCase() ==
                                              alias.toLowerCase())
                                          .firstOrNull;
                                      if (exTxn?.categoryId != null) {
                                        chosenCat = exTxn!.categoryId!;
                                        chosenSubCat = exTxn.subCategory;
                                      }
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 14),
                        ],
                      );
                    },
                  ),
                  TextField(
                    key: const Key('review-custom-alias-input'),
                    controller: controller,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Custom Alias / Nickname',
                      hintText: 'e.g. My Maid, Juice Corner, Office Tea',
                      hintStyle:
                          const TextStyle(color: Colors.white24, fontSize: 12),
                      labelStyle: const TextStyle(
                          color: AppColors.primaryLight, fontSize: 12),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.label_outline,
                          color: AppColors.primaryLight, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Default Category:',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        key: Key('review-custom-alias-category-${txn.id}'),
                        value: chosenCat,
                        dropdownColor: const Color(0xFF1E293B),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                        icon: const Icon(Icons.keyboard_arrow_down,
                            color: Colors.white54, size: 16),
                        isExpanded: true,
                        items: _categories
                            .map((c) =>
                                DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              chosenCat = val;
                              final subs = _subCategories[val] ?? [];
                              chosenSubCat =
                                  subs.isNotEmpty ? subs.first : null;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  if (chosenCat != 'Not Applicable / Exclude') ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Default Sub-Category:',
                            style:
                                TextStyle(color: Colors.white54, fontSize: 12)),
                        GestureDetector(
                          onTap: () async {
                            final newSub =
                                await _promptAddSubCategory(context, chosenCat);
                            if (newSub != null) {
                              setDialogState(() => chosenSubCat = newSub);
                            }
                          },
                          child: const Row(
                            children: [
                              Icon(Icons.add,
                                  size: 13, color: AppColors.primaryLight),
                              SizedBox(width: 2),
                              Text('Add Sub',
                                  style: TextStyle(
                                      color: AppColors.primaryLight,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0x3338BDF8)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          key: Key('review-custom-alias-subcategory-${txn.id}'),
                          value: (availableSubs.contains(chosenSubCat) &&
                                  chosenSubCat != null)
                              ? chosenSubCat
                              : (availableSubs.isNotEmpty
                                  ? availableSubs.first
                                  : null),
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(
                              color: Color(0xFF93C5FD),
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                          icon: const Icon(Icons.keyboard_arrow_down,
                              color: Colors.white54, size: 16),
                          isExpanded: true,
                          items: availableSubs
                              .map((s) =>
                                  DropdownMenuItem(value: s, child: Text(s)))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => chosenSubCat = val);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton.icon(
                key: const Key('review-save-custom-alias'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  final name = controller.text.trim();
                  if (name.isNotEmpty) {
                    Navigator.of(ctx).pop({
                      'alias': name,
                      'category': chosenCat,
                      'subCategory': chosenSubCat,
                    });
                  }
                },
                icon: const Icon(Icons.check, size: 16, color: Colors.white),
                label: const Text('Save Custom Alias',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    if (result != null &&
        result['alias'] != null &&
        result['alias']!.isNotEmpty) {
      final name = result['alias']!;
      final cat = result['category'] ?? chosenCat;
      final sub = result['subCategory'];

      setState(() {
        _selectedEntities[txn.id] = name;
        _selectedCategories[txn.id] = cat;
        if (sub != null && sub.isNotEmpty) {
          _selectedSubCategories[txn.id] = sub;
        }
      });
      unawaited(EntityService().mapTransactionToEntity(
        entityName: name,
        rawVendorName: rawVendorName,
        upiId: vpa,
        accountMask: accountMask,
        category: cat,
        subCategory: sub,
        mapByUpiOnly: isAggregator,
      ));
    }
  }

  String? _extractSnippetDate(TransactionItem txn) {
    final text = '${txn.rawSnippet ?? ''} ${txn.merchantName}';
    final match = RegExp(r'\bon\s+(\d{1,2})[-/](\d{1,2})[-/](\d{2,4})\b',
            caseSensitive: false)
        .firstMatch(text);
    return match?.group(1);
  }

  TransactionItem? _findDuplicate(TransactionItem item, int currentIndex) {
    final canonicalId = item.potentialDuplicateOfTransactionId;
    if (canonicalId == null || canonicalId.isEmpty) {
      return null;
    }
    for (final transaction in [
      ...widget.pendingTransactions,
      ...?widget.existingTransactions
    ]) {
      if (transaction.id == canonicalId) {
        return transaction;
      }
    }
    return null;
  }

  TransactionItem? _findSelfTransferPair(
      TransactionItem item, int currentIndex) {
    if (item.amount <= 0) return null;
    final acct1 = _getDisplayAccountMask(item);
    final text1 = '${item.rawSnippet ?? ''} ${item.merchantName}'.toLowerCase();

    // 1. Search pending transactions
    for (int i = 0; i < widget.pendingTransactions.length; i++) {
      if (i == currentIndex) continue;
      final other = widget.pendingTransactions[i];
      if ((other.amount - item.amount).abs() > 0.01) continue;
      if (item.categoryId == 'Bills & Utilities' ||
          other.categoryId == 'Bills & Utilities') continue;

      final isOpposite = (item.type == 'DEBIT' &&
              (other.type == 'CREDIT' || other.type == 'TRANSFER')) ||
          ((item.type == 'CREDIT' || item.type == 'TRANSFER') &&
              other.type == 'DEBIT');
      if (!isOpposite) continue;

      final date1 = _extractSnippetDate(item);
      final date2 = _extractSnippetDate(other);
      final sameDate = (date1 != null && date2 != null && date1 == date2) ||
          (item.timestamp.year == other.timestamp.year &&
              item.timestamp.month == other.timestamp.month &&
              item.timestamp.day == other.timestamp.day);
      final closeInTime =
          item.timestamp.difference(other.timestamp).abs().inHours <= 12;
      if (!sameDate && !closeInTime) continue;

      final acct2 = _getDisplayAccountMask(other);
      final text2 =
          '${other.rawSnippet ?? ''} ${other.merchantName}'.toLowerCase();

      final differentAccounts =
          acct1 != null && acct2 != null && acct1 != acct2;
      final hasSelfName = text1.contains('rakshith') ||
          text2.contains('rakshith') ||
          text1.contains('7813004130') ||
          text2.contains('7813004130');
      final hasTransferWord =
          text1.contains('transfer') || text2.contains('transfer');

      if (differentAccounts || hasSelfName || hasTransferWord) {
        return other;
      }
    }

    // 2. Search existingTransactions
    if (widget.existingTransactions != null) {
      for (final existing in widget.existingTransactions!) {
        if ((existing.amount - item.amount).abs() > 0.01) continue;
        final isOpposite = (item.type == 'DEBIT' &&
                (existing.type == 'CREDIT' || existing.type == 'TRANSFER')) ||
            ((item.type == 'CREDIT' || item.type == 'TRANSFER') &&
                existing.type == 'DEBIT');
        if (!isOpposite) continue;

        final date1 = _extractSnippetDate(item);
        final date2 = _extractSnippetDate(existing);
        final sameDate = (date1 != null && date2 != null && date1 == date2) ||
            (item.timestamp.year == existing.timestamp.year &&
                item.timestamp.month == existing.timestamp.month &&
                item.timestamp.day == existing.timestamp.day);
        final closeInTime =
            item.timestamp.difference(existing.timestamp).abs().inHours <= 12;
        if (!sameDate && !closeInTime) continue;

        final acct2 = _getDisplayAccountMask(existing);
        final text2 = '${existing.rawSnippet ?? ''} ${existing.merchantName}'
            .toLowerCase();
        final differentAccounts =
            acct1 != null && acct2 != null && acct1 != acct2;
        final hasSelfName = text1.contains('rakshith') ||
            text2.contains('rakshith') ||
            text1.contains('7813004130') ||
            text2.contains('7813004130');

        if (differentAccounts || hasSelfName) {
          return existing;
        }
      }
    }

    return null;
  }

  String _getDisplayMerchant(TransactionItem txn) {
    final isAggregator = EntityService.isPlatformAggregator(txn.merchantName);
    final isSelfName = txn.merchantName.toLowerCase().contains('rakshith') &&
        !txn.merchantName.toLowerCase().contains('salary');
    if (!isAggregator &&
        !isSelfName &&
        txn.merchantName.isNotEmpty &&
        !txn.merchantName.startsWith('❗') &&
        !txn.merchantName.startsWith('Alert') &&
        !txn.merchantName.toLowerCase().contains('you have done a upi') &&
        !txn.merchantName.toLowerCase().contains('payment was made using') &&
        !txn.merchantName.toLowerCase().contains('bill payment processed') &&
        txn.merchantName != 'Bank Alert' &&
        txn.merchantName != 'Bank Transfer' &&
        txn.merchantName != 'Email Transaction') {
      return txn.merchantName;
    }
    // Fallback extraction from rawSnippet or merchantName
    final text = '${txn.merchantName} ${txn.rawSnippet ?? ''}';
    final vpaStr = (_getDisplayVpa(txn) ?? '').toLowerCase();
    final lowerCombined = '$text $vpaStr'.toLowerCase();

    // 0. Self Transfer check
    if ((lowerCombined.contains('rakshith') ||
            vpaStr.contains('7813004130') ||
            lowerCombined.contains('self transfer')) &&
        !lowerCombined.contains('salary')) {
      return 'Self Transfer';
    }

    // 0a. Platform / Aggregator VPA handles (e.g. cred.fastag@axisb, cred.rent@axisb)
    if (lowerCombined.contains('cred.fastag') ||
        (vpaStr.contains('fastag') && lowerCombined.contains('dreamplug'))) {
      return 'CRED (FASTag Recharge)';
    } else if (lowerCombined.contains('cred.rent') ||
        (vpaStr.contains('rent') && lowerCombined.contains('dreamplug'))) {
      return 'CRED (House Rent)';
    } else if (lowerCombined.contains('cred.club') ||
        lowerCombined.contains('cred.store')) {
      return 'CRED Store';
    } else if (lowerCombined.contains('cred.bills') ||
        lowerCombined.contains('cred.utility')) {
      return 'CRED (Bill Payment)';
    } else if (vpaStr.contains('fastag')) {
      return 'FASTag Recharge';
    } else if (lowerCombined.contains('dreamplug')) {
      return 'CRED';
    }

    // 0b. Loan EMI Deduction (e.g. "added to EMI 150250733 Chq...")
    if (RegExp(
            r'added\s+to\s+EMI|\btowards\s+EMI|\bloan\s+account|\bEMI\s+\d{4,16}',
            caseSensitive: false)
        .hasMatch(text)) {
      final emiMatch = RegExp(
              r'(?:added\s+to\s+EMI|towards\s+EMI|\bEMI)\s*([xX*]*\d{4,16})',
              caseSensitive: false)
          .firstMatch(text);
      String loanMask = '';
      if (emiMatch != null && emiMatch.group(1) != null) {
        final g = emiMatch.group(1)!;
        loanMask = '•••• ${g.substring(g.length >= 4 ? g.length - 4 : 0)}';
      }
      final bankMatch = RegExp(
              r'\b(HDFC|ICICI|SBI|AXIS|KOTAK|RBL|YES|IDFC|BOB|PNB|CANARA|INDUSIND)\s+Bank',
              caseSensitive: false)
          .firstMatch(text);
      final bankName =
          bankMatch != null ? '${bankMatch.group(1)} Bank' : 'Bank';
      return loanMask.isNotEmpty
          ? '$bankName Loan EMI ($loanMask)'
          : '$bankName Loan EMI';
    }

    // 1. Recurring Deposit / Investment
    if (RegExp(r'recurring\s+deposit|\brd\s*no\b', caseSensitive: false)
        .hasMatch(text)) {
      final rdMatch =
          RegExp(r'(?:RD|FD)\s*No\.?\s*([xX*]*\d{4})', caseSensitive: false)
              .firstMatch(text);
      if (rdMatch != null && rdMatch.group(1) != null) {
        final last4 = rdMatch.group(1)!.substring(rdMatch.group(1)!.length - 4);
        return 'Recurring Deposit (RD •••• $last4)';
      }
      return 'Recurring Deposit';
    }

    // 2. NEFT / IMPS Salary & Inflow
    final neftMatch = RegExp(
            r'(?:NEFT\s+Cr-[A-Za-z0-9]+-|Cr-)([A-Za-z0-9\s&]+?)(?:-[A-Za-z0-9\s]+-[A-Za-z0-9]+|$)',
            caseSensitive: false)
        .firstMatch(text);
    if (neftMatch != null && neftMatch.group(1) != null) {
      var rawName = neftMatch.group(1)!.trim();
      rawName = rawName
          .replaceAll(
              RegExp(r'\s*SALARY\s*TRANSIT\s*AC|\s*TRANSIT\s*AC',
                  caseSensitive: false),
              '')
          .trim();
      if (rawName.length > 2) return rawName;
    }

    // 3. Credit Card Bill Repayment
    final cardMatch = RegExp(
            r'towards\s+your\s+([A-Za-z0-9\s&]+?Credit\s+Card)',
            caseSensitive: false)
        .firstMatch(text);
    if (cardMatch != null && cardMatch.group(1) != null) {
      return cardMatch.group(1)!.trim();
    }

    // 4. UPI VPA
    final nameInParen = RegExp(
            r'towards\s+(?:VPA\s+)?[A-Za-z0-9._@-]+(?:\s*\(([^)]+)\))',
            caseSensitive: false)
        .firstMatch(text);
    if (nameInParen != null && nameInParen.group(1) != null) {
      return nameInParen.group(1)!.trim();
    }

    // 5. Merchant after to/at/towards/paid to
    final toMatch = RegExp(
            r'(?:to|at|towards|for|paid\s+to)\s+([A-Za-z0-9_.\-&/ ]{2,32}?)(?:\s+on\s+\d|\s+dated|\.|\,|$)',
            caseSensitive: false)
        .firstMatch(text);
    if (toMatch != null && toMatch.group(1) != null) {
      final candidate = toMatch.group(1)!.trim();
      if (!candidate.toLowerCase().contains('your account') &&
          !candidate.toLowerCase().contains('credit card ending') &&
          !candidate.toLowerCase().contains('check details') &&
          candidate.toLowerCase() != 'bank alert') {
        return candidate;
      }
    }
    return (txn.merchantName.isNotEmpty && txn.merchantName != 'Bank Alert')
        ? txn.merchantName
        : 'Bank Transfer';
  }

  String? _getDisplayVpa(TransactionItem txn) {
    if (txn.referenceNumber != null && txn.referenceNumber!.isNotEmpty) {
      return txn.referenceNumber;
    }
    final text = '${txn.merchantName} ${txn.rawSnippet ?? ''}';
    final vpaMatch = RegExp(
            r'(?:towards\s+VPA\s+|VPA\s+|vpa:?\s*)([A-Za-z0-9._@-]+)',
            caseSensitive: false)
        .firstMatch(text);
    if (vpaMatch != null) return vpaMatch.group(1);
    return null;
  }

  String? _getDisplayAccountMask(TransactionItem txn) {
    if (txn.accountMask != null && txn.accountMask!.isNotEmpty) {
      return txn.accountMask;
    }
    final text = '${txn.merchantName} ${txn.rawSnippet ?? ''}';
    final acctMatch = RegExp(
            r'(?:account|a\/c|card)\s*(?:ending|no\.?|number|ending with)?\s*(?:in|:)?\s*[:\s]*([xX*]*\d{4})',
            caseSensitive: false)
        .firstMatch(text);
    if (acctMatch != null) {
      final digits = acctMatch.group(1)!.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length >= 4) {
        return '•••• ${digits.substring(digits.length - 4)}';
      }
    }
    return null;
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final dateStr =
        isToday ? 'Today' : '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final minuteStr = dt.minute.toString().padLeft(2, '0');
    return '$dateStr, $hour:$minuteStr $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final invalidCount =
        widget.pendingTransactions.where((t) => t.amount <= 0).length;

    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.rate_review_outlined,
                      color: AppColors.primaryLight, size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    'Review Transactions',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${widget.pendingTransactions.length}',
                      style: const TextStyle(
                          color: AppColors.primaryLight,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          if (invalidCount > 0 && widget.onPurgeInvalid != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0x22F59E0B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_delete_outlined,
                      color: Color(0xFFFBBF24), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$invalidCount promo / ₹0.00 items detected',
                      style: const TextStyle(
                          color: Color(0xFFFDE68A), fontSize: 12),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFBBF24),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                    ),
                    icon: const Icon(Icons.delete_sweep, size: 16),
                    label: const Text('Purge All',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12)),
                    onPressed: () {
                      widget.onPurgeInvalid!();
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (widget.pendingTransactions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.check_circle_outline,
                        color: Color(0xFF34D399), size: 36),
                    SizedBox(height: 8),
                    Text('All transactions reviewed!',
                        style: TextStyle(color: Colors.white70, fontSize: 14)),
                  ],
                ),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.pendingTransactions.length,
                itemBuilder: (context, index) {
                  final txn = widget.pendingTransactions[index];
                  final duplicateTarget = _findDuplicate(txn, index);
                  final isDup = duplicateTarget != null;
                  final selfTransferPair = _findSelfTransferPair(txn, index);
                  final isTransfer = selfTransferPair != null ||
                      txn.isTransfer ||
                      (_selectedCategories[txn.id] == 'Self Transfer');
                  final selectedCategory = _selectedCategories[txn.id] ??
                      (isTransfer ? 'Self Transfer' : 'Food & Dining');

                  final displayMerchant = _getDisplayMerchant(txn);
                  final displayVpa = _getDisplayVpa(txn);
                  final displayAccount = _getDisplayAccountMask(txn);
                  final pairAccount = selfTransferPair != null
                      ? _getDisplayAccountMask(selfTransferPair)
                      : null;
                  final formattedTime = _formatTimestamp(txn.timestamp);
                  final isCredit = txn.type == 'CREDIT';
                  final isSaving = _confirmingTransactionId == txn.id;
                  final currentEntity = _selectedEntities[txn.id] ??
                      (isTransfer ? 'Self Transfer' : displayMerchant);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: isTransfer
                              ? const Color(0x6606B6D4)
                              : Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Row 1: Type Badge, Merchant/Payee Name, Amount
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isTransfer
                                    ? const Color(0x2206B6D4)
                                    : (isCredit
                                        ? const Color(0x2210B981)
                                        : const Color(0x22EF4444)),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                isTransfer
                                    ? Icons.swap_horiz_rounded
                                    : (isCredit
                                        ? Icons.arrow_downward
                                        : Icons.arrow_upward),
                                color: isTransfer
                                    ? const Color(0xFF22D3EE)
                                    : (isCredit
                                        ? const Color(0xFF34D399)
                                        : const Color(0xFFF87171)),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          currentEntity,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            letterSpacing: 0.2,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      InkWell(
                                        borderRadius: BorderRadius.circular(4),
                                        onTap: () => _promptSetCustomAlias(
                                          context,
                                          txn,
                                          currentEntity,
                                          displayMerchant,
                                          displayVpa,
                                          displayAccount,
                                        ),
                                        child: const Tooltip(
                                          message:
                                              'Set custom alias / nickname',
                                          child: Padding(
                                            padding: EdgeInsets.all(2.0),
                                            child: Icon(Icons.edit_note,
                                                size: 20,
                                                color: AppColors.primaryLight),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isTransfer
                                        ? (txn.type == 'DEBIT'
                                            ? 'Self Transfer (Debit / Outflow)'
                                            : 'Self Transfer (Credit / Inflow)')
                                        : (currentEntity.toLowerCase() !=
                                                displayMerchant.toLowerCase()
                                            ? 'Vendor: $displayMerchant • ${isCredit ? "Credit / Received" : "Debit / Paid"}'
                                            : (isCredit
                                                ? 'Credit / Received'
                                                : 'Debit / Paid')),
                                    style: TextStyle(
                                      color: isTransfer
                                          ? const Color(0xFF22D3EE)
                                          : (isCredit
                                              ? const Color(0xFF34D399)
                                              : const Color(0xFFF87171)),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Builder(
                              builder: (ctx) {
                                final displayAmount =
                                    _overrideAmounts[txn.id] ?? txn.amount;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    InkWell(
                                      key: Key('review-amount-${txn.id}'),
                                      borderRadius: BorderRadius.circular(6),
                                      onTap: () =>
                                          _promptEditAmount(context, txn),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: (displayAmount <= 0)
                                              ? const Color(0x22F59E0B)
                                              : Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: (displayAmount <= 0)
                                              ? Border.all(
                                                  color:
                                                      const Color(0xFFF59E0B),
                                                  width: 1)
                                              : null,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              displayAmount > 0
                                                  ? '${txn.currency} ${displayAmount.toStringAsFixed(2)}'
                                                  : 'Set Bill Amount ✎',
                                              style: TextStyle(
                                                color: (displayAmount <= 0)
                                                    ? const Color(0xFFF59E0B)
                                                    : (isCredit
                                                        ? const Color(
                                                            0xFF34D399)
                                                        : const Color(
                                                            0xFFF87171)),
                                                fontWeight: FontWeight.bold,
                                                fontSize: (displayAmount <= 0)
                                                    ? 12
                                                    : 16,
                                              ),
                                            ),
                                            if (displayAmount > 0) ...[
                                              const SizedBox(width: 4),
                                              const Icon(Icons.edit,
                                                  size: 12,
                                                  color: Colors.white38),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      formattedTime,
                                      style: const TextStyle(
                                          color: Colors.white38, fontSize: 11),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        // Row 2: Account & UPI VPA metadata tags
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            if (displayAccount != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E293B),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.white10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.credit_card,
                                        size: 12, color: Colors.white70),
                                    const SizedBox(width: 4),
                                    Text(
                                      'A/C: $displayAccount',
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                            if (displayVpa != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E293B),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.white10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.alternate_email,
                                        size: 12, color: Color(0xFF60A5FA)),
                                    const SizedBox(width: 4),
                                    Text(
                                      displayVpa,
                                      style: const TextStyle(
                                          color: Color(0xFF93C5FD),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF334155),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Source: ${txn.ingestionSource}',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 11),
                              ),
                            ),
                            if (selfTransferPair != null || isTransfer)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0x3306B6D4),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: const Color(0x8806B6D4)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.swap_horiz_rounded,
                                        size: 13, color: Color(0xFF22D3EE)),
                                    const SizedBox(width: 4),
                                    Text(
                                      pairAccount != null
                                          ? 'Self-Transfer (${displayAccount ?? "A/C"} ⇄ $pairAccount)'
                                          : 'Self-Transfer',
                                      style: const TextStyle(
                                        color: Color(0xFF22D3EE),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else if (isDup)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0x33F59E0B),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: const Color(0x88F59E0B)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.warning_amber_rounded,
                                        size: 12, color: Color(0xFFFBBF24)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Duplicate of: ${_getDisplayMerchant(duplicateTarget)}',
                                      style: const TextStyle(
                                        color: Color(0xFFFBBF24),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0x333B82F6),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Needs Review',
                                  style: TextStyle(
                                    color: Color(0xFF60A5FA),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),

                        // Row 3: Bank Email Quote / Snippet Evidence
                        if ((txn.rawSnippet != null &&
                                txn.rawSnippet!.isNotEmpty) ||
                            (txn.merchantName.isNotEmpty &&
                                txn.merchantName.length > 30)) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B)
                                  .withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('💬 ',
                                    style: TextStyle(fontSize: 12)),
                                Expanded(
                                  child: Text(
                                    txn.rawSnippet ?? txn.merchantName,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      height: 1.3,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Row 3.2: Self-Transfer Pair Banner
                        if (selfTransferPair != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0x1A06B6D4),
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: const Color(0x3306B6D4)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.sync_alt_rounded,
                                    color: Color(0xFF22D3EE), size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '🔁 Self-Transfer Detected: ${txn.type == "DEBIT" ? "Debit from" : "Credit to"} ${displayAccount ?? "Account"} (${txn.type == "DEBIT" ? "➔ Sent to" : "➔ Received from"} ${pairAccount ?? "Account"}). Net expense impact: ₹0.00.',
                                    style: const TextStyle(
                                        color: Color(0xFFA5F3FC),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Row 3.5: Loan Account Detection & Setup Action
                        if (_isLoanEmiTransaction(txn)) ...[
                          const SizedBox(height: 10),
                          Builder(
                            builder: (ctx) {
                              final loanMask = _extractLoanAccountMask(txn);
                              final rawDigits = loanMask != null
                                  ? loanMask.replaceAll(RegExp(r'[^0-9]'), '')
                                  : '';
                              final existingLoan =
                                  widget.existingAccounts?.firstWhere(
                                (a) =>
                                    a.type == 'LOAN' &&
                                    rawDigits.isNotEmpty &&
                                    a.lastFourDigits == rawDigits,
                                orElse: () => FinancialAccount(
                                    id: '',
                                    name: '',
                                    type: '',
                                    lastFourDigits: '',
                                    currency: '',
                                    currentBalance: 0),
                              );
                              final hasLinkedLoan = existingLoan != null &&
                                  existingLoan.id.isNotEmpty;

                              return Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF2A153D),
                                      Color(0xFF1E1035)
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: const Color(0xFF8B5CF6)
                                          .withValues(alpha: 0.5)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: const Color(0x338B5CF6),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.account_balance,
                                          color: Color(0xFFA78BFA), size: 16),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            hasLinkedLoan
                                                ? 'Linked to Loan: ${existingLoan.name}'
                                                : 'EMI Loan Account (${loanMask ?? "•••• 0733"})',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            hasLinkedLoan
                                                ? 'Tracked in your accounts. Tap Edit to update details.'
                                                : 'Create a loan account to track principal, EMI & remaining tenure',
                                            style: const TextStyle(
                                                color: Colors.white60,
                                                fontSize: 10),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: hasLinkedLoan
                                            ? const Color(0xFF334155)
                                            : const Color(0xFF8B5CF6),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                      ),
                                      icon: Icon(
                                          hasLinkedLoan
                                              ? Icons.edit
                                              : Icons.add_circle_outline,
                                          size: 14),
                                      label: Text(
                                        hasLinkedLoan
                                            ? 'Edit Loan'
                                            : 'Setup Loan',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600),
                                      ),
                                      onPressed: () =>
                                          _showLoanAccountSetupDialog(
                                              context, txn),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],

                        const SizedBox(height: 10),

                        // Row 4: Entity / Merchant Mapping Row
                        Builder(
                          builder: (context) {
                            final allEntities = EntityService().entities;
                            final entityNames = <String>{};
                            for (final e in allEntities) {
                              if (e.name.isNotEmpty &&
                                  e.name != 'Self Transfer') {
                                entityNames.add(e.name);
                              }
                            }
                            if (widget.existingTransactions != null) {
                              for (final t in widget.existingTransactions!) {
                                if (t.merchantName.isNotEmpty &&
                                    t.merchantName != 'Self Transfer' &&
                                    t.merchantName != 'Bank Alert') {
                                  entityNames.add(t.merchantName);
                                }
                              }
                            }
                            for (final t in widget.pendingTransactions) {
                              if (t.merchantName.isNotEmpty &&
                                  t.merchantName != 'Self Transfer' &&
                                  t.merchantName != 'Bank Alert') {
                                entityNames.add(t.merchantName);
                              }
                            }

                            final currentEntity =
                                _selectedEntities[txn.id] ?? displayMerchant;
                            entityNames.add(currentEntity);
                            if (displayMerchant.isNotEmpty) {
                              entityNames.add(displayMerchant);
                            }
                            final entityOptions = entityNames.toList()..sort();

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text('Alias / Entity: ',
                                        style: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 12)),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1E293B),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border:
                                              Border.all(color: Colors.white12),
                                        ),
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<String>(
                                            value: currentEntity,
                                            dropdownColor:
                                                const Color(0xFF1E293B),
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600),
                                            icon: const Icon(
                                                Icons.keyboard_arrow_down,
                                                color: Colors.white54,
                                                size: 16),
                                            isExpanded: true,
                                            items: entityOptions
                                                .map((e) => DropdownMenuItem(
                                                    value: e, child: Text(e)))
                                                .toList(),
                                            onChanged: (val) {
                                              if (val != null) {
                                                setState(() {
                                                  _selectedEntities[txn.id] =
                                                      val;
                                                  final matched = EntityService()
                                                      .entities
                                                      .where((e) =>
                                                          e.name
                                                              .toLowerCase() ==
                                                          val.toLowerCase())
                                                      .firstOrNull;
                                                  if (matched
                                                          ?.defaultCategory !=
                                                      null) {
                                                    _selectedCategories[
                                                            txn.id] =
                                                        matched!
                                                            .defaultCategory!;
                                                    if (matched.defaultSubCategory !=
                                                            null &&
                                                        matched
                                                            .defaultSubCategory!
                                                            .isNotEmpty) {
                                                      _selectedSubCategories[
                                                          txn
                                                              .id] = matched
                                                          .defaultSubCategory!;
                                                    }
                                                  } else {
                                                    final exTxn = widget
                                                        .existingTransactions
                                                        ?.where((t) =>
                                                            t.merchantName
                                                                .toLowerCase() ==
                                                            val.toLowerCase())
                                                        .firstOrNull;
                                                    if (exTxn?.categoryId !=
                                                        null) {
                                                      _selectedCategories[
                                                              txn.id] =
                                                          exTxn!.categoryId!;
                                                      if (exTxn.subCategory !=
                                                              null &&
                                                          exTxn.subCategory!
                                                              .isNotEmpty) {
                                                        _selectedSubCategories[
                                                                txn.id] =
                                                            exTxn.subCategory!;
                                                      }
                                                    }
                                                  }
                                                });
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Tooltip(
                                      message:
                                          'Set custom alias / nickname for this vendor',
                                      child: ElevatedButton.icon(
                                        icon: const Icon(Icons.edit_note,
                                            size: 15, color: Colors.white),
                                        label: const Text('Custom Alias',
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF2563EB),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 9, vertical: 8),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8)),
                                        ),
                                        onPressed: () => _promptSetCustomAlias(
                                          context,
                                          txn,
                                          currentEntity,
                                          displayMerchant,
                                          displayVpa,
                                          displayAccount,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.link,
                                        size: 12, color: Color(0xFF60A5FA)),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        displayVpa != null &&
                                                displayVpa.isNotEmpty
                                            ? 'Maps vendor "$displayMerchant" & UPI "$displayVpa" to "$currentEntity"'
                                            : 'Maps vendor "$displayMerchant" to "$currentEntity"',
                                        style: const TextStyle(
                                            color: Color(0xFF93C5FD),
                                            fontSize: 11,
                                            fontStyle: FontStyle.italic),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),

                        const SizedBox(height: 10),

                        // Row 5: Category & Sub-Category Dropdown & Actions
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Parent Category
                            Row(
                              children: [
                                const Text('Category: ',
                                    style: TextStyle(
                                        color: Colors.white54, fontSize: 12)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E293B),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: selectedCategory ==
                                                'Not Applicable / Exclude'
                                            ? const Color(0xFFF97316)
                                            : Colors.white12,
                                      ),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: selectedCategory,
                                        dropdownColor: const Color(0xFF1E293B),
                                        style: TextStyle(
                                          color: selectedCategory ==
                                                  'Not Applicable / Exclude'
                                              ? const Color(0xFFF97316)
                                              : Colors.white,
                                          fontSize: 12,
                                          fontWeight: selectedCategory ==
                                                  'Not Applicable / Exclude'
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                        icon: const Icon(
                                            Icons.keyboard_arrow_down,
                                            color: Colors.white54,
                                            size: 16),
                                        isExpanded: true,
                                        items: _categories
                                            .map((c) => DropdownMenuItem(
                                                  value: c,
                                                  child: Text(
                                                    c,
                                                    style: TextStyle(
                                                      color: c ==
                                                              'Not Applicable / Exclude'
                                                          ? const Color(
                                                              0xFFF97316)
                                                          : Colors.white,
                                                    ),
                                                  ),
                                                ))
                                            .toList(),
                                        onChanged: (val) {
                                          if (val != null) {
                                            setState(() {
                                              _selectedCategories[txn.id] = val;
                                              final subs =
                                                  _subCategories[val] ?? [];
                                              _selectedSubCategories[txn.id] =
                                                  subs.isNotEmpty
                                                      ? subs.first
                                                      : '';
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Tooltip(
                                  message: 'Mark as Promotional / Spam email',
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.block,
                                        size: 13, color: Color(0xFFF97316)),
                                    label: const Text('Promo',
                                        style: TextStyle(
                                            color: Color(0xFFF97316),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600)),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                          color: Color(0x66F97316)),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 8),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                    ),
                                    onPressed: () {
                                      widget.onMarkPromotional?.call(txn);
                                      setState(() {});
                                    },
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  tooltip: 'Dismiss / Not a transaction',
                                  icon: const Icon(Icons.delete_outline,
                                      color: Color(0xFFEF4444), size: 20),
                                  onPressed: () {
                                    widget.onDismiss(txn);
                                    setState(() {});
                                  },
                                ),
                              ],
                            ),

                            // Sub-Category Row
                            if (selectedCategory !=
                                'Not Applicable / Exclude') ...[
                              const SizedBox(height: 8),
                              Builder(
                                builder: (ctx) {
                                  final availableSubs =
                                      _subCategories[selectedCategory] ?? [];
                                  final currentSub =
                                      _selectedSubCategories[txn.id] ??
                                          (availableSubs.isNotEmpty
                                              ? availableSubs.first
                                              : '');
                                  final subOptions =
                                      availableSubs.toSet().toList();
                                  if (currentSub.isNotEmpty &&
                                      !subOptions.contains(currentSub)) {
                                    subOptions.insert(0, currentSub);
                                  }

                                  return Row(
                                    children: [
                                      const Text('Sub-Category: ',
                                          style: TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1E293B),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                                color: const Color(0x3338BDF8)),
                                          ),
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              value: subOptions
                                                      .contains(currentSub)
                                                  ? currentSub
                                                  : (subOptions.isNotEmpty
                                                      ? subOptions.first
                                                      : null),
                                              dropdownColor:
                                                  const Color(0xFF1E293B),
                                              style: const TextStyle(
                                                  color: Color(0xFF93C5FD),
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600),
                                              icon: const Icon(
                                                  Icons.keyboard_arrow_down,
                                                  color: Colors.white54,
                                                  size: 16),
                                              isExpanded: true,
                                              items: subOptions
                                                  .map((s) => DropdownMenuItem(
                                                      value: s, child: Text(s)))
                                                  .toList(),
                                              onChanged: (val) {
                                                if (val != null) {
                                                  setState(() =>
                                                      _selectedSubCategories[
                                                          txn.id] = val);
                                                }
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Tooltip(
                                        message:
                                            'Add new sub-category under "$selectedCategory"',
                                        child: OutlinedButton.icon(
                                          icon: const Icon(Icons.add,
                                              size: 13,
                                              color: AppColors.primaryLight),
                                          label: const Text('New Sub',
                                              style: TextStyle(
                                                  color: AppColors.primaryLight,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600)),
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(
                                                color: Color(0x663B82F6)),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 8),
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8)),
                                          ),
                                          onPressed: () async {
                                            final created =
                                                await _promptAddSubCategory(
                                                    context, selectedCategory);
                                            if (created != null) {
                                              setState(() =>
                                                  _selectedSubCategories[
                                                      txn.id] = created);
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Row 6: Action Buttons
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                key: Key('review-confirm-${txn.id}'),
                                onPressed: isSaving
                                    ? null
                                    : () async {
                                        final chosenEntity =
                                            _selectedEntities[txn.id] ??
                                                displayMerchant;
                                        final chosenSub =
                                            _selectedSubCategories[txn.id];

                                        final finalAmount =
                                            _overrideAmounts[txn.id] ??
                                                txn.amount;
                                        final pairAccountMask =
                                            selfTransferPair != null
                                                ? (_getDisplayAccountMask(
                                                        selfTransferPair) ??
                                                    selfTransferPair
                                                        .accountMask)
                                                : null;

                                        final updatedTxn = txn.copyWith(
                                          amount: finalAmount,
                                          merchantName: chosenEntity,
                                          categoryId: selectedCategory,
                                          subCategory: chosenSub,
                                          accountMask:
                                              displayAccount ?? txn.accountMask,
                                          transferCounterpartMask:
                                              txn.transferCounterpartMask ??
                                                  pairAccountMask,
                                        );

                                        setState(() {
                                          _confirmingTransactionId = txn.id;
                                          _confirmationErrorTransactionId =
                                              null;
                                          _confirmationErrorMessage = null;
                                        });
                                        var saved = false;
                                        try {
                                          saved = await widget.onConfirm(
                                              updatedTxn, selectedCategory);
                                        } catch (_) {}
                                        if (!mounted) return;
                                        if (!saved) {
                                          setState(() {
                                            _confirmingTransactionId = null;
                                            _confirmationErrorTransactionId =
                                                txn.id;
                                            _confirmationErrorMessage = widget
                                                    .confirmationErrorMessage
                                                    ?.call() ??
                                                'Unable to save this category rule. Please try again.';
                                          });
                                          return;
                                        }

                                        unawaited(EntityService()
                                            .mapTransactionToEntity(
                                          entityName: chosenEntity,
                                          rawVendorName: displayMerchant,
                                          upiId: displayVpa,
                                          accountMask: displayAccount,
                                          category: selectedCategory,
                                          subCategory: chosenSub,
                                        ));

                                        // Auto-create loan account if this is an EMI transaction and not yet created
                                        if (_isLoanEmiTransaction(txn) &&
                                            widget.onCreateLoanAccount !=
                                                null) {
                                          final loanMask =
                                              _extractLoanAccountMask(txn);
                                          final rawDigits = loanMask != null
                                              ? loanMask.replaceAll(
                                                  RegExp(r'[^0-9]'), '')
                                              : '0733';
                                          final alreadyExists = widget
                                                  .existingAccounts
                                                  ?.any((a) =>
                                                      a.type == 'LOAN' &&
                                                      a.lastFourDigits ==
                                                          rawDigits) ??
                                              false;
                                          if (!alreadyExists) {
                                            final autoLoan = FinancialAccount(
                                              id: 'acc-loan-${DateTime.now().millisecondsSinceEpoch}',
                                              name: chosenEntity.isNotEmpty
                                                  ? chosenEntity
                                                  : 'Loan Account (•••• $rawDigits)',
                                              type: 'LOAN',
                                              lastFourDigits: rawDigits,
                                              currency: 'INR',
                                              currentBalance: 0.0,
                                              emiAmount: finalAmount,
                                              completedInstallments: 1,
                                            );
                                            widget
                                                .onCreateLoanAccount!(autoLoan);
                                          }
                                        }

                                        if (mounted) {
                                          setState(() {
                                            _confirmingTransactionId = null;
                                          });
                                          if (widget.pendingTransactions
                                                  .isEmpty &&
                                              Navigator.canPop(this.context)) {
                                            Navigator.of(this.context).pop();
                                          }
                                        }
                                      },
                                icon: isSaving
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.check_circle_outline,
                                        size: 16),
                                label: Text(
                                  isSaving
                                      ? 'Saving category rule...'
                                      : selectedCategory == 'Self Transfer'
                                          ? 'Confirm Transfer'
                                          : (isCredit
                                              ? 'Confirm Inflow'
                                              : 'Confirm Expense'),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      selectedCategory == 'Self Transfer'
                                          ? const Color(0xFF0891B2)
                                          : (isCredit
                                              ? const Color(0xFF10B981)
                                              : const Color(0xFF22C55E)),
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            if (selfTransferPair != null &&
                                widget.pendingTransactions.any(
                                    (p) => p.id == selfTransferPair.id)) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: isSaving
                                      ? null
                                      : () async {
                                          final finalAmount =
                                              _overrideAmounts[txn.id] ??
                                                  txn.amount;
                                          final thisAcct =
                                              displayAccount ?? txn.accountMask;
                                          final thatAcct = pairAccount ??
                                              selfTransferPair.accountMask;

                                          final updatedTxn = txn.copyWith(
                                            amount: finalAmount,
                                            merchantName: 'Self Transfer',
                                            categoryId: 'Self Transfer',
                                            subCategory: _selectedSubCategories[
                                                    txn.id] ??
                                                'Account to Account Transfer',
                                            reconciliationStatus: 'CONFIRMED',
                                            accountMask: thisAcct,
                                            transferCounterpartMask: thatAcct,
                                          );
                                          final updatedPair =
                                              selfTransferPair.copyWith(
                                            amount: finalAmount,
                                            merchantName: 'Self Transfer',
                                            categoryId: 'Self Transfer',
                                            subCategory:
                                                'Account to Account Transfer',
                                            reconciliationStatus: 'CONFIRMED',
                                            accountMask: thatAcct,
                                            transferCounterpartMask: thisAcct,
                                          );

                                          setState(() {
                                            _confirmingTransactionId = txn.id;
                                            _confirmationErrorTransactionId =
                                                null;
                                          });
                                          var firstSaved = false;
                                          var secondSaved = false;
                                          try {
                                            firstSaved = await widget.onConfirm(
                                                updatedTxn, 'Self Transfer');
                                            secondSaved = firstSaved &&
                                                await widget.onConfirm(
                                                    updatedPair,
                                                    'Self Transfer');
                                          } catch (_) {}
                                          if (!mounted) return;
                                          if (!secondSaved) {
                                            setState(() {
                                              _confirmingTransactionId = null;
                                              _confirmationErrorTransactionId =
                                                  txn.id;
                                            });
                                            return;
                                          }
                                          setState(() {
                                            _confirmingTransactionId = null;
                                          });
                                          if (widget.pendingTransactions
                                                  .isEmpty &&
                                              Navigator.canPop(this.context)) {
                                            Navigator.of(this.context).pop();
                                          }
                                        },
                                  icon: const Icon(Icons.swap_horiz_rounded,
                                      size: 16),
                                  label: const Text('1-Tap Confirm Pair'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0891B2),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                            ] else if (isDup) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    await widget.onMerge(duplicateTarget, txn);
                                    if (!mounted) return;
                                    if (mounted) {
                                      setState(() {});
                                      if (widget.pendingTransactions.isEmpty &&
                                          Navigator.canPop(context)) {
                                        Navigator.of(context).pop();
                                      }
                                    }
                                  },
                                  icon: const Icon(Icons.merge_type, size: 16),
                                  label: const Text('1-Tap Merge'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF3B82F6),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (_confirmationErrorTransactionId == txn.id) ...[
                          const SizedBox(height: 8),
                          Text(
                            _confirmationErrorMessage ??
                                'Unable to save this category rule. Please try again.',
                            style: const TextStyle(
                              color: Color(0xFFFCA5A5),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

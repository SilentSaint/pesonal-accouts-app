import 'package:flutter/foundation.dart';
import '../domain/peer_debt_entry.dart';

class PeerDebtState extends ChangeNotifier {
  static final PeerDebtState _instance = PeerDebtState._internal();
  factory PeerDebtState() => _instance;
  PeerDebtState._internal();

  final List<PeerDebtEntry> _debts = [];

  List<PeerDebtEntry> get debts => List.unmodifiable(_debts);
  List<PeerDebtEntry> get activeDebts => _debts.where((d) => !d.isSettled).toList();
  List<PeerDebtEntry> get settledDebts => _debts.where((d) => d.isSettled).toList();

  void recordDirectDebt({
    required String contactName,
    required double amount,
    required bool isLent,
    String description = '',
    DateTime? dueDate,
    String currency = 'INR',
  }) {
    final entry = PeerDebtEntry(
      id: 'debt-${DateTime.now().millisecondsSinceEpoch}',
      contactName: contactName.trim(),
      amount: amount,
      currency: currency,
      description: description.trim(),
      isLent: isLent,
      isSettled: false,
      createdAt: DateTime.now(),
      dueDate: dueDate,
    );
    _debts.insert(0, entry);
    notifyListeners();
  }

  void markAs100PercentLent({
    required String transactionId,
    required String contactName,
    required double amount,
    required String merchantName,
    required String currency,
  }) {
    final entry = PeerDebtEntry(
      id: 'debt-txn-$transactionId',
      contactName: contactName.trim(),
      amount: amount,
      currency: currency,
      description: '$merchantName (100% Lent)',
      isLent: true,
      isSettled: false,
      transactionId: transactionId,
      createdAt: DateTime.now(),
    );
    _debts.insert(0, entry);
    notifyListeners();
  }

  void splitTransaction({
    required String transactionId,
    required String merchantName,
    required String currency,
    required List<Map<String, dynamic>> splits,
  }) {
    for (final s in splits) {
      final String name = s['contactName'] ?? '';
      final double amt = (s['amount'] as num?)?.toDouble() ?? 0.0;
      final String note = s['note'] ?? '';
      final entry = PeerDebtEntry(
        id: 'split-$transactionId-${name.hashCode}',
        contactName: name.trim(),
        amount: amt,
        currency: currency,
        description: note.isNotEmpty ? '$merchantName - $note' : '$merchantName (Split share)',
        isLent: true,
        isSettled: false,
        transactionId: transactionId,
        createdAt: DateTime.now(),
      );
      _debts.insert(0, entry);
    }
    notifyListeners();
  }

  void settleDebt(String debtId, [double? amount]) {
    final idx = _debts.indexWhere((d) => d.id == debtId);
    if (idx == -1) return;

    final existing = _debts[idx];
    final payAmount = amount ?? existing.remainingAmount;
    final newSettled = existing.settledAmount + payAmount;
    final isFullySettled = newSettled >= (existing.amount - 0.01);

    _debts[idx] = existing.copyWith(
      settledAmount: newSettled,
      isSettled: isFullySettled,
    );
    notifyListeners();
  }

  List<ContactDebtSummary> get contactSummaries {
    final Map<String, List<PeerDebtEntry>> byContact = {};
    for (final d in _debts) {
      byContact.putIfAbsent(d.contactName, () => []).add(d);
    }

    final List<ContactDebtSummary> result = [];
    byContact.forEach((contact, list) {
      double lent = 0.0;
      double borrowed = 0.0;
      int activeCount = 0;

      for (final e in list) {
        if (!e.isSettled) activeCount++;
        final rem = e.remainingAmount;
        if (e.isLent) {
          lent += rem;
        } else {
          borrowed += rem;
        }
      }

      result.add(
        ContactDebtSummary(
          contactName: contact,
          netBalance: lent - borrowed,
          totalLent: lent,
          totalBorrowed: borrowed,
          activeDebtCount: activeCount,
        ),
      );
    });

    return result;
  }
}

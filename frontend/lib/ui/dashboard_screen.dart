import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/financial_account.dart';
import '../domain/transaction_item.dart';
import '../domain/peer_debt_entry.dart';
import '../domain/expense_categories.dart';
import '../services/peer_debt_service.dart';
import 'theme/app_theme.dart';
import 'uncategorized_review_banner.dart';
import 'historical_backfill_card.dart';
import 'category_breakdown_view.dart';
import 'transaction_review_modal.dart';
import 'email_settings_screen.dart';
import 'peer_debt_screen.dart';
import 'loan_tracking_screen.dart';
import 'card_emi_screen.dart';
import 'bill_tracker_screen.dart';
import 'budget_screen.dart';
import 'analytics_screen.dart';
import 'financial_context_screen.dart';
import 'income_source_screen.dart';
import 'split_expense_modal.dart';
import '../services/websocket_sync_service.dart';
import '../services/security_service.dart';
import '../services/sms_receiver_service.dart';
import '../services/backend_api_service.dart';
import '../application/sms_ingestion_service.dart';
import '../domain/sms_ingestion_port.dart';
import '../infrastructure/android_sms_ingestion_adapter.dart';
import '../services/entity_service.dart';
import '../services/auth_service.dart';
import '../services/gmail_scan_service.dart';
import '../services/auto_scan_scheduler_service.dart';
import '../services/developer_mode_service.dart';
import '../services/financial_data_cache.dart';
import 'developer_audit_panel.dart';

class DashboardScreen extends StatefulWidget {
  final List<TransactionItem>? initialPendingTransactions;
  final List<TransactionItem>? initialRecentTransactions;
  final List<FinancialAccount>? initialAccounts;
  final Future<TransactionItem?> Function(TransactionItem transaction)?
  onReviewConfirmation;
  const DashboardScreen({
    super.key,
    this.initialPendingTransactions,
    this.initialRecentTransactions,
    this.initialAccounts,
    this.onReviewConfirmation,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  bool isScanning30Days = false;
  bool isHistoricalBackfilled = false;
  DateTime? lastBackfillScanTime;
  final PeerDebtState peerDebtState = PeerDebtState();
  final WebSocketSyncService syncService = WebSocketSyncService();

  final List<FinancialAccount> accounts = [];
  final Map<String, double> categoryTotals = {};
  final List<TransactionItem> pendingTransactions = [];
  final List<TransactionItem> recentTransactions = [];
  final SmsIngestionService _smsIngestion = SmsIngestionService(
    AndroidSmsIngestionAdapter(),
  );
  SmsCaptureStatus? _smsCaptureStatus;
  Timer? _smsRetryTimer;
  Future<void>? _persistentStateLoad;

  @override
  void initState() {
    super.initState();
    if (widget.initialPendingTransactions != null) {
      pendingTransactions.addAll(widget.initialPendingTransactions!);
    }
    if (widget.initialRecentTransactions != null) {
      recentTransactions.addAll(widget.initialRecentTransactions!);
    }
    if (widget.initialAccounts != null) {
      accounts.addAll(widget.initialAccounts!);
    }
    if (recentTransactions.isNotEmpty) {
      _reconcileSelfTransfers();
    }
    peerDebtState.addListener(_onStateChange);
    AuthService().addListener(_onAuthStateChanged);
    syncService.addListener(_onSyncStateChanged);
    syncService.onSyncEvent = (_) => _recoverFromSync();
    syncService.onReconnected = _recoverFromSync;
    WidgetsBinding.instance.addObserver(this);
    _loadPersistentState();
    AuthService().ensureInitialized().then((_) {
      if (AuthService().isAuthenticated) unawaited(syncService.connect());
    });
    _initializeSmsCapture();
    _initAutoScanScheduler();
    _smsRetryTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _drainSmsCaptureQueue(),
    );
  }

  void _onAuthStateChanged() {
    if (mounted) {
      final auth = AuthService();
      if (!auth.isInitialized) {
        setState(() {});
        return;
      }
      setState(() {});
      if (auth.isAuthenticated) {
        _loadPersistentState();
        _initAutoScanScheduler();
        unawaited(syncService.connect());
      } else {
        AutoScanSchedulerService().stop();
        unawaited(syncService.disconnect());
        // Preserve explicit fixture data supplied through the widget seam.
        // Normal app startup never supplies this data, so sign-out still
        // clears the live dashboard state.
        if (widget.initialAccounts == null &&
            widget.initialRecentTransactions == null &&
            widget.initialPendingTransactions == null) {
          setState(() {
            accounts.clear();
            recentTransactions.clear();
            pendingTransactions.clear();
            categoryTotals.clear();
            isHistoricalBackfilled = false;
            lastBackfillScanTime = null;
          });
        }
      }
    }
  }

  void _initAutoScanScheduler() {
    final scheduler = AutoScanSchedulerService();
    scheduler.removeListener(_onSchedulerStateChanged);
    scheduler.addListener(_onSchedulerStateChanged);
    scheduler.onTriggerScan =
        ({afterTimestamp, beforeTimestamp, required scanType}) async {
          debugPrint(
            'Dashboard: automated scan triggered for $scanType (after: $afterTimestamp, before: $beforeTimestamp)',
          );
          await _triggerFinancialEmailScan(
            afterTimestamp: afterTimestamp,
            beforeTimestamp: beforeTimestamp,
            isScheduledScan: true,
          );
        };
    scheduler.start();
  }

  void _onSchedulerStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initializeSmsCapture() async {
    await _smsIngestion.initialize(_drainSmsCaptureQueue);
    await _refreshSmsCaptureStatus();
    await _drainSmsCaptureQueue();
  }

  Future<void> _refreshSmsCaptureStatus() async {
    final status = await _smsIngestion.captureStatus();
    if (mounted) setState(() => _smsCaptureStatus = status);
  }

  Future<void> _requestSmsCaptureAuthorization() async {
    final status = await _smsIngestion.requestCaptureAuthorization();
    if (mounted) setState(() => _smsCaptureStatus = status);
    if (status.isCapturing) await _drainSmsCaptureQueue();
  }

  Future<void> _drainSmsCaptureQueue() async {
    if (!AuthService().isAuthenticated) return;
    await _smsIngestion.drain(_submitCapturedSms);
  }

  Future<bool> _submitCapturedSms(
    TransactionItem transaction,
    SmsCaptureEvent event,
  ) async {
    if (!AuthService().isAuthenticated) return false;
    final account = FinancialAccount(
      id: transaction.accountId,
      name: '${event.bankName} A/C',
      type: 'SAVINGS',
      lastFourDigits: event.accountLastFour,
      currency: 'INR',
      currentBalance: 0,
    );
    final isNewAccount = !accounts.any(
      (item) => item.lastFourDigits == account.lastFourDigits,
    );
    final isNewTransaction = !recentTransactions.any(
      (item) => item.id == transaction.id,
    );
    final categoryId = transaction.categoryId ?? 'General Expenses';
    if (mounted) {
      setState(() {
        if (isNewAccount) {
          accounts.add(account);
        }
        _addConfirmedTransaction(transaction);
        if (isNewTransaction && transaction.type == 'DEBIT') {
          categoryTotals[categoryId] =
              (categoryTotals[categoryId] ?? 0) + transaction.amount;
        }
      });
      await _savePersistentState(
        isHistoricalBackfilled,
        lastBackfillScanTime ?? DateTime.now(),
      );
    }
    if (isNewAccount) {
      await BackendApiService().createAccount(account);
    }
    return BackendApiService().createTransaction(transaction);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshSmsCaptureStatus();
      _drainSmsCaptureQueue();
      if (AuthService().isAuthenticated) unawaited(syncService.connect());
    }
  }

  bool _isDueOrBillNotice(String text) {
    final lower = text.toLowerCase();
    final hasDueRegex = RegExp(
      r'\b(?:due\s+date|payment\s+due(?:\s+date)?|amount\s+due|total\s+(?:amount\s+)?due|minimum\s+(?:amount\s+)?due|is\s+due(?:\s+on)?|due\s+on\s+[0-9a-z]|due\s+by\s+[0-9a-z]|due\s+today|overdue|payable\s+by|last\s+date\s+(?:to\s+pay|of\s+payment)|pay\s+before\s+due|avoid\s+late\s+fees|pay\s+now\s+on\s+cred|bill\s+(?:is\s+)?due)\b',
      caseSensitive: false,
    );
    return hasDueRegex.hasMatch(lower) ||
        lower.contains('due date:') ||
        lower.contains('amount due:') ||
        lower.contains('due on:') ||
        lower.contains('total due:') ||
        lower.contains('min due:');
  }

  Future<void> _loadPersistentState() {
    final inFlight = _persistentStateLoad;
    if (inFlight != null) return inFlight;

    late final Future<void> load;
    load = _loadPersistentStateImpl().whenComplete(() {
      if (identical(_persistentStateLoad, load)) {
        _persistentStateLoad = null;
      }
    });
    _persistentStateLoad = load;
    return load;
  }

  Future<void> _loadPersistentStateImpl() async {
    await AuthService().ensureInitialized();
    final authenticatedUser = AuthService().currentUser;
    if (authenticatedUser == null) {
      return;
    }
    await EntityService().ensureLoaded();
    if (AuthService().currentUser?.id != authenticatedUser.id) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();

    int? currentVer;
    try {
      currentVer = prefs.getInt('app_data_version');
    } catch (_) {
      try {
        final s = prefs.getString('app_data_version');
        if (s != null) currentVer = int.tryParse(s);
      } catch (_) {}
    }

    if (currentVer != null && currentVer < 5) {
      await FinancialDataCache(prefs).clear();
      await prefs.remove('user_account_email');
      await prefs.remove('user_account_name');
      await prefs.remove('user_account_id');
      await prefs.setInt('app_data_version', 5);
    }

    bool backfilled = false;
    try {
      backfilled = prefs.getBool('is_historical_backfilled') ?? false;
    } catch (_) {
      try {
        backfilled = prefs.getString('is_historical_backfilled') == 'true';
      } catch (_) {}
    }

    int? lastTimeMs;
    try {
      lastTimeMs = prefs.getInt('last_backfill_scan_ms');
    } catch (_) {
      try {
        final s = prefs.getString('last_backfill_scan_ms');
        if (s != null) lastTimeMs = int.tryParse(s);
      } catch (_) {}
    }

    String? rawAccounts;
    try {
      rawAccounts = prefs.getString('saved_accounts');
    } catch (_) {}

    String? rawRecentTxns;
    try {
      rawRecentTxns = prefs.getString('saved_recent_txns');
    } catch (_) {}

    String? rawPendingTxns;
    try {
      rawPendingTxns = prefs.getString('saved_pending_txns');
    } catch (_) {}

    String? rawCategoryTotals;
    try {
      rawCategoryTotals = prefs.getString('saved_category_totals');
    } catch (_) {}

    if (mounted && AuthService().currentUser?.id == authenticatedUser.id) {
      setState(() {
        isHistoricalBackfilled = backfilled;
        if (lastTimeMs != null) {
          lastBackfillScanTime = DateTime.fromMillisecondsSinceEpoch(
            lastTimeMs,
          );
        }

        if (rawAccounts != null) {
          try {
            final List<dynamic> list = jsonDecode(rawAccounts);
            accounts.clear();
            accounts.addAll(
              list.map(
                (e) => FinancialAccount.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              ),
            );
          } catch (e) {
            debugPrint('Error parsing saved_accounts: $e');
          }
        }

        if (rawRecentTxns != null) {
          try {
            final List<dynamic> list = jsonDecode(rawRecentTxns);
            recentTransactions.clear();
            recentTransactions.addAll(
              list.map(
                (e) => TransactionItem.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              ),
            );
            recentTransactions.sort(
              (a, b) => b.timestamp.compareTo(a.timestamp),
            );
          } catch (_) {}
        }

        if (rawPendingTxns != null) {
          try {
            final List<dynamic> list = jsonDecode(rawPendingTxns);
            final blacklist =
                (prefs.getStringList('saved_promotional_blacklist') ?? [])
                    .map((e) => e.toLowerCase())
                    .toList();

            pendingTransactions.clear();
            pendingTransactions.addAll(
              list
                  .map(
                    (e) => TransactionItem.fromJson(
                      Map<String, dynamic>.from(e as Map),
                    ),
                  )
                  .where((t) {
                    if (t.amount <= 0) return false;
                    final fullText = '${t.merchantName} ${t.rawSnippet ?? ''}'
                        .toLowerCase();
                    if (blacklist.any(
                      (b) => b.isNotEmpty && fullText.contains(b),
                    ))
                      return false;
                    if (_isDueOrBillNotice(fullText)) return false;
                    if ((fullText.contains('cashback') &&
                            fullText.contains('win')) ||
                        fullText.contains('chance to win') ||
                        fullText.contains('fastag 🚗') ||
                        fullText.contains('#paytmkaro')) {
                      return false;
                    }
                    return true;
                  }),
            );
            pendingTransactions.sort(
              (a, b) => b.timestamp.compareTo(a.timestamp),
            );
          } catch (_) {}
        }

        if (rawCategoryTotals != null) {
          try {
            final Map<String, dynamic> map = jsonDecode(rawCategoryTotals);
            categoryTotals.clear();
            map.forEach((k, v) {
              categoryTotals[k] = (v as num).toDouble();
            });
          } catch (_) {}
        }

        final Set<String> knownLast4 = accounts
            .map((a) => a.lastFourDigits)
            .toSet();
        for (final t in recentTransactions) {
          _ensureMaskRegistered(t.accountMask, knownLast4);
          _ensureMaskRegistered(t.transferCounterpartMask, knownLast4);
          if (t.merchantName.isNotEmpty &&
              t.merchantName != 'Self Transfer' &&
              t.merchantName != 'Bank Alert') {
            EntityService().registerDiscoveredMerchant(
              name: t.merchantName,
              category: t.categoryId,
              subCategory: t.subCategory,
              upiId: t.referenceNumber,
              accountMask: t.accountMask,
            );
          }
        }
        _reconcileSelfTransfers();
      });
    }

    if (AuthService().currentUser?.id == authenticatedUser.id) {
      try {
        final cloudAccounts = await BackendApiService().fetchAccounts();
        final cloudTxns = await BackendApiService().fetchTransactions();
        final reviewQueue = await BackendApiService()
            .fetchReconciliationReviewQueue();
        if (mounted &&
            AuthService().currentUser?.id == authenticatedUser.id &&
            (cloudAccounts.isNotEmpty ||
                cloudTxns.isNotEmpty ||
                reviewQueue != null)) {
          setState(() {
            if (cloudAccounts.isNotEmpty) {
              accounts.clear();
              accounts.addAll(cloudAccounts);
            }
            if (cloudTxns.isNotEmpty) {
              recentTransactions.clear();
              recentTransactions.addAll(cloudTxns);
              recentTransactions.sort(
                (a, b) => b.timestamp.compareTo(a.timestamp),
              );
              categoryTotals.clear();
              for (final t in cloudTxns) {
                if (t.type == 'DEBIT' &&
                    !t.isTransfer &&
                    t.categoryId != 'Self Transfer') {
                  final cat = t.categoryId ?? 'General Expenses';
                  categoryTotals[cat] = (categoryTotals[cat] ?? 0.0) + t.amount;
                }
                if (reviewQueue != null) {
                  pendingTransactions
                    ..clear()
                    ..addAll(reviewQueue.pendingTransactions);
                  pendingTransactions.sort(
                    (a, b) => b.timestamp.compareTo(a.timestamp),
                  );
                  for (final canonical in reviewQueue.canonicalTransactions) {
                    if (!recentTransactions.any(
                      (item) => item.id == canonical.id,
                    )) {
                      recentTransactions.add(canonical);
                    }
                  }
                }
              }
            }
            final Set<String> knownCloudLast4 = accounts
                .map((a) => a.lastFourDigits)
                .toSet();
            for (final t in recentTransactions) {
              _ensureMaskRegistered(t.accountMask, knownCloudLast4);
              _ensureMaskRegistered(t.transferCounterpartMask, knownCloudLast4);
            }
            _reconcileSelfTransfers();
            isHistoricalBackfilled = true;
          });
          _savePersistentState(
            isHistoricalBackfilled,
            lastBackfillScanTime ?? DateTime.now(),
            expectedUserId: authenticatedUser.id,
          );
        }
      } catch (_) {}
    }
    await _drainSmsCaptureQueue();
  }

  bool _isCurrentAuthenticatedUser(String userId) =>
      AuthService().currentUser?.id == userId;

  Future<void> _savePersistentState(
    bool backfilled,
    DateTime scanTime, {
    String? expectedUserId,
  }) async {
    final userId = expectedUserId ?? AuthService().currentUser?.id;
    if (userId == null || !_isCurrentAuthenticatedUser(userId)) return;

    final prefs = await SharedPreferences.getInstance();
    if (!_isCurrentAuthenticatedUser(userId)) return;
    await prefs.setBool(FinancialDataCache.backfillCompleteKey, backfilled);
    if (!_isCurrentAuthenticatedUser(userId)) return;
    await prefs.setInt(
      FinancialDataCache.backfillTimeKey,
      scanTime.millisecondsSinceEpoch,
    );
    if (!_isCurrentAuthenticatedUser(userId)) return;
    await prefs.setString(
      FinancialDataCache.accountsKey,
      jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );
    if (!_isCurrentAuthenticatedUser(userId)) return;
    await prefs.setString(
      FinancialDataCache.recentTransactionsKey,
      jsonEncode(recentTransactions.map((t) => t.toJson()).toList()),
    );
    if (!_isCurrentAuthenticatedUser(userId)) return;
    await prefs.setString(
      FinancialDataCache.pendingTransactionsKey,
      jsonEncode(pendingTransactions.map((t) => t.toJson()).toList()),
    );
    if (!_isCurrentAuthenticatedUser(userId)) return;
    await prefs.setString(
      FinancialDataCache.categoryTotalsKey,
      jsonEncode(categoryTotals),
    );
  }

  void _addConfirmedTransaction(TransactionItem txn) {
    recentTransactions.removeWhere(
      (t) =>
          t.id == txn.id ||
          (txn.referenceNumber != null &&
              txn.referenceNumber!.isNotEmpty &&
              t.referenceNumber == txn.referenceNumber),
    );
    recentTransactions.add(txn);
    recentTransactions.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    _ensureMaskRegistered(txn.accountMask);
    _ensureMaskRegistered(txn.transferCounterpartMask);
  }

  void _ensureMaskRegistered(
    String? mask, [
    Set<String>? knownLast4,
    String? suggestedType,
    String? suggestedName,
  ]) {
    if (mask == null || mask.isEmpty) return;
    final digits = mask.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 2) return;
    final last4 = digits.length >= 4
        ? digits.substring(digits.length - 4)
        : digits;

    if (knownLast4 != null) {
      if (knownLast4.contains(last4)) return;
      knownLast4.add(last4);
    } else {
      if (accounts.any(
        (a) => a.lastFourDigits == last4 || a.id.contains(last4),
      ))
        return;
    }

    final isCredit =
        last4 == '9207' ||
        last4 == '9635' ||
        suggestedType == 'CREDIT_CARD' ||
        recentTransactions.any(
          (t) =>
              (t.accountMask?.contains(last4) ?? false) &&
              ((t.rawSnippet?.toLowerCase().contains('credit card') ?? false) ||
                  (t.merchantName.toLowerCase().contains('credit card')) ||
                  (t.subCategory?.toLowerCase().contains('credit card') ??
                      false)),
        );

    final accType = isCredit ? 'CREDIT_CARD' : (suggestedType ?? 'SAVINGS');
    final defaultName =
        suggestedName ??
        (isCredit
            ? (last4 == '9207'
                  ? 'HDFC Credit Card (•••• $last4)'
                  : (last4 == '9635'
                        ? 'RBL Credit Card (•••• $last4)'
                        : 'Credit Card (•••• $last4)'))
            : (last4 == '1277'
                  ? 'HDFC Bank (•••• $last4)'
                  : 'Bank Account (•••• $last4)'));

    final newAcc = FinancialAccount(
      id: 'acc-$last4',
      name: defaultName,
      type: accType,
      lastFourDigits: last4,
      currentBalance: 0.0,
      currency: 'INR',
    );
    accounts.add(newAcc);
    if (AuthService().isAuthenticated) {
      BackendApiService().createAccount(newAcc);
    }
  }

  String? _extractMaskFromSnippet(String? snippet) {
    if (snippet == null || snippet.isEmpty) return null;
    final text = snippet
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"');

    final match =
        RegExp(
          r'(?:ending\s+(?:in\s+|with\s+)?|account\s*(?:no\.?|number|ending)?|a\/c\s*(?:no\.?|number|ending)?|credit\s+card|card|acct)\s*[:\s-]*\(?([xX*.]*\d{2,6})\)?',
          caseSensitive: false,
        ).firstMatch(text) ??
        RegExp(
          r'\b(?:XX|xx|\*\*|\.\.\.|••••)\s*(\d{2,4})\b',
        ).firstMatch(text) ??
        RegExp(
          r'\baccount\s*[:\s]*[xX*]*(\d{4})\b',
          caseSensitive: false,
        ).firstMatch(text);

    if (match != null) {
      final raw = match.group(1) ?? match.group(0)!;
      final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length >= 2) {
        final last4 = digits.length >= 4
            ? digits.substring(digits.length - 4)
            : digits;
        return '•••• $last4';
      }
    }
    return null;
  }

  String? _findCounterpartTransferMask(TransactionItem txn) {
    for (final other in recentTransactions) {
      if (other.id == txn.id) continue;
      if (!other.isTransfer && other.categoryId != 'Self Transfer') continue;
      if ((other.amount - txn.amount).abs() > 0.01) continue;

      final isOpposite =
          (txn.type == 'DEBIT' &&
              (other.type == 'CREDIT' || other.type == 'TRANSFER')) ||
          ((txn.type == 'CREDIT' || txn.type == 'TRANSFER') &&
              other.type == 'DEBIT');
      if (!isOpposite) continue;

      final timeDiff = txn.timestamp.difference(other.timestamp).abs().inHours;
      if (timeDiff <= 24) {
        final mask = (other.accountMask ?? '').replaceAll('→', '').trim();
        if (mask.isNotEmpty && mask.length >= 4) return mask;
        final extracted = _extractMaskFromSnippet(other.rawSnippet);
        if (extracted != null && extracted.isNotEmpty) return extracted;
      }
    }
    return null;
  }

  String _getSelfTransferRouteText(TransactionItem txn) {
    String cleanMask(String? m) => (m ?? '').replaceAll('→', '').trim();
    String? myMask = cleanMask(txn.accountMask);
    if (myMask.isEmpty || myMask.length < 4) {
      myMask = _extractMaskFromSnippet(txn.rawSnippet);
    }
    String? counterpart = cleanMask(txn.transferCounterpartMask);
    if (counterpart.isEmpty || counterpart.length < 4) {
      counterpart = _findCounterpartTransferMask(txn);
    }

    final isDebit = txn.type == 'DEBIT';
    final from = isDebit ? myMask : counterpart;
    final to = isDebit ? counterpart : myMask;

    if (from != null &&
        from.isNotEmpty &&
        to != null &&
        to.isNotEmpty &&
        from != to) {
      return '$from → $to';
    }
    if (from != null && from.isNotEmpty) {
      return '$from ➔ Transfer';
    }
    if (to != null && to.isNotEmpty) {
      return '➔ $to Transfer';
    }
    return 'Internal ⇄';
  }

  void _reconcileSelfTransfers() {
    bool changed = false;

    // 1. Clean up and extract any missing or malformed accountMask in recentTransactions
    for (int i = 0; i < recentTransactions.length; i++) {
      final t = recentTransactions[i];
      final snippetMask = _extractMaskFromSnippet(t.rawSnippet);

      String? cleanAcct = t.accountMask != null
          ? t.accountMask!.replaceAll('→', '').trim()
          : null;
      if (cleanAcct == null ||
          cleanAcct.isEmpty ||
          cleanAcct.length < 4 ||
          (t.accountMask != null && t.accountMask!.contains('→'))) {
        cleanAcct = snippetMask ?? cleanAcct;
      }
      if (snippetMask != null &&
          snippetMask.isNotEmpty &&
          (t.type == 'CREDIT' || t.isTransfer)) {
        cleanAcct = snippetMask;
      }

      String? cleanCounterpart = t.transferCounterpartMask != null
          ? t.transferCounterpartMask!.replaceAll('→', '').trim()
          : null;
      if (cleanCounterpart != null &&
          (cleanCounterpart.isEmpty || cleanCounterpart.length < 4)) {
        cleanCounterpart = null;
      }

      if (cleanAcct != t.accountMask ||
          cleanCounterpart != t.transferCounterpartMask) {
        recentTransactions[i] = t.copyWith(
          accountMask: cleanAcct,
          transferCounterpartMask: cleanCounterpart,
        );
        changed = true;
      }
    }

    // 2. Find matching debit and credit self-transfer pairs in recentTransactions
    final transfers = recentTransactions
        .where((t) => t.isTransfer || t.categoryId == 'Self Transfer')
        .toList();
    for (final debit in transfers.where((t) => t.type == 'DEBIT')) {
      for (final credit in transfers.where(
        (t) => t.type == 'CREDIT' || t.type == 'TRANSFER',
      )) {
        if ((debit.amount - credit.amount).abs() > 0.01) continue;
        final timeDiff = debit.timestamp
            .difference(credit.timestamp)
            .abs()
            .inHours;
        if (timeDiff > 24) continue;

        String? debitMask = debit.accountMask != null
            ? debit.accountMask!.replaceAll('→', '').trim()
            : null;
        if (debitMask == null || debitMask.length < 4) {
          debitMask = _extractMaskFromSnippet(debit.rawSnippet);
        }

        String? creditMask = credit.accountMask != null
            ? credit.accountMask!.replaceAll('→', '').trim()
            : null;
        if (creditMask == null || creditMask.length < 4) {
          creditMask = _extractMaskFromSnippet(credit.rawSnippet);
        }

        if (debitMask != null &&
            creditMask != null &&
            debitMask != creditMask) {
          final dIdx = recentTransactions.indexWhere((t) => t.id == debit.id);
          if (dIdx != -1) {
            final curD = recentTransactions[dIdx];
            if (curD.accountMask != debitMask ||
                curD.transferCounterpartMask != creditMask) {
              recentTransactions[dIdx] = curD.copyWith(
                accountMask: debitMask,
                transferCounterpartMask: creditMask,
              );
              changed = true;
            }
          }

          final cIdx = recentTransactions.indexWhere((t) => t.id == credit.id);
          if (cIdx != -1) {
            final curC = recentTransactions[cIdx];
            if (curC.accountMask != creditMask ||
                curC.transferCounterpartMask != debitMask) {
              recentTransactions[cIdx] = curC.copyWith(
                accountMask: creditMask,
                transferCounterpartMask: debitMask,
              );
              changed = true;
            }
          }

          _ensureMaskRegistered(debitMask);
          _ensureMaskRegistered(creditMask);
        }
      }
    }

    // 3. Audit accounts to classify Credit Cards (e.g. 9207, 9635)
    for (int i = 0; i < accounts.length; i++) {
      final a = accounts[i];
      final isCard =
          a.lastFourDigits == '9207' ||
          a.lastFourDigits == '9635' ||
          recentTransactions.any(
            (t) =>
                (t.accountMask?.contains(a.lastFourDigits) ?? false) &&
                ((t.rawSnippet?.toLowerCase().contains('credit card') ??
                        false) ||
                    (t.merchantName.toLowerCase().contains('credit card')) ||
                    (t.subCategory?.toLowerCase().contains('credit card') ??
                        false)),
          );
      if (isCard && a.type != 'CREDIT_CARD') {
        final cardName = a.lastFourDigits == '9207'
            ? 'HDFC Credit Card (•••• 9207)'
            : (a.lastFourDigits == '9635'
                  ? 'RBL Credit Card (•••• 9635)'
                  : 'Credit Card (•••• ${a.lastFourDigits})');
        accounts[i] = a.copyWith(type: 'CREDIT_CARD', name: cardName);
        changed = true;
      }
    }

    _computeAccountBalances();

    if (changed) {
      _savePersistentState(
        isHistoricalBackfilled,
        lastBackfillScanTime ?? DateTime.now(),
      );
      if (AuthService().isAuthenticated) {
        for (final t in recentTransactions.where(
          (x) => x.isTransfer || x.categoryId == 'Self Transfer',
        )) {
          BackendApiService().createTransaction(t);
        }
      }
    }
  }

  DateTime? _parseIndianDate(String dateStr) {
    try {
      final parts = dateStr.split('-');
      if (parts.length == 3) {
        final day = int.tryParse(parts[0]);
        final monthStr = parts[1].toUpperCase();
        var year = int.tryParse(parts[2]);
        if (year != null && year < 100) year += 2000;
        final months = {
          'JAN': 1,
          'FEB': 2,
          'MAR': 3,
          'APR': 4,
          'MAY': 5,
          'JUN': 6,
          'JUL': 7,
          'AUG': 8,
          'SEP': 9,
          'OCT': 10,
          'NOV': 11,
          'DEC': 12,
        };
        final month = months[monthStr];
        if (day != null && month != null && year != null) {
          return DateTime(year, month, day);
        }
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic>? _extractBalanceSnapshotFromSnippet(
    String? snippet,
    String? dateStr,
  ) {
    if (snippet == null || snippet.isEmpty) return null;
    final text = snippet
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"');

    final balMatch = RegExp(
      r'(?:available\s+balance\s+in\s+your\s+account|available\s+bal\s+in\s+your\s+a\/c|available\s+balance\s+is).*?(?:rs\.?|inr)\s*([0-9,]+(?:\.\d{2})?)',
      caseSensitive: false,
    ).firstMatch(text);

    if (balMatch != null &&
        !RegExp(
          r'(?:debited|spent|paid|transferred\s+to)',
          caseSensitive: false,
        ).hasMatch(text)) {
      final rawBal = balMatch.group(1)!.replaceAll(',', '');
      final bal = double.tryParse(rawBal);
      final mask = _extractMaskFromSnippet(text);
      DateTime? asOf;
      final dateMatch = RegExp(
        r'\bas\s+on\s+(\d{1,2}-[A-Za-z]{3}-\d{2,4})',
        caseSensitive: false,
      ).firstMatch(text);
      if (dateMatch != null) {
        asOf = _parseIndianDate(dateMatch.group(1)!);
      } else if (dateStr != null) {
        asOf = DateTime.tryParse(dateStr);
      }
      if (bal != null && bal > 0 && mask != null) {
        return {
          'mask': mask,
          'balance': bal,
          'asOfDate': asOf ?? DateTime.now(),
        };
      }
    }
    return null;
  }

  void _computeAccountBalances() {
    final Map<String, List<Map<String, dynamic>>> snapshotsByLast4 = {};

    for (final acc in accounts) {
      if (acc.anchorBalance != null && acc.anchorDate != null) {
        snapshotsByLast4.putIfAbsent(acc.lastFourDigits, () => []).add({
          'balance': acc.anchorBalance!,
          'asOfDate': acc.anchorDate!,
        });
      }
    }

    for (final t in recentTransactions) {
      final snap = _extractBalanceSnapshotFromSnippet(
        t.rawSnippet,
        t.timestamp.toIso8601String(),
      );
      if (snap != null) {
        final digits = (snap['mask'] as String).replaceAll(
          RegExp(r'[^0-9]'),
          '',
        );
        final last4 = digits.length >= 4
            ? digits.substring(digits.length - 4)
            : digits;
        snapshotsByLast4.putIfAbsent(last4, () => []).add({
          'balance': snap['balance'] as double,
          'asOfDate': snap['asOfDate'] as DateTime,
        });
      }
    }

    for (int i = 0; i < accounts.length; i++) {
      final acc = accounts[i];
      final last4 = acc.lastFourDigits;

      Map<String, dynamic>? latestSnap;
      final snaps = snapshotsByLast4[last4];
      if (snaps != null && snaps.isNotEmpty) {
        snaps.sort(
          (a, b) =>
              (b['asOfDate'] as DateTime).compareTo(a['asOfDate'] as DateTime),
        );
        latestSnap = snaps.first;
      }

      double calculatedBalance = 0.0;
      DateTime? anchorDate;
      double? anchorBal;

      if (latestSnap != null) {
        anchorBal = latestSnap['balance'] as double;
        anchorDate = latestSnap['asOfDate'] as DateTime;
        calculatedBalance = anchorBal;

        for (final t in recentTransactions) {
          final isDebitLeg =
              (t.accountMask?.contains(last4) ?? false) ||
              t.accountId.contains(last4);
          final isCreditLeg =
              (t.transferCounterpartMask?.contains(last4) ?? false);

          if (t.timestamp.isAfter(anchorDate) ||
              (t.timestamp.year == anchorDate.year &&
                  t.timestamp.month == anchorDate.month &&
                  t.timestamp.day == anchorDate.day)) {
            if (acc.isCreditCard) {
              if (isDebitLeg && t.type == 'DEBIT') {
                calculatedBalance += t.amount;
              } else if (t.type == 'CREDIT') {
                calculatedBalance -= t.amount;
              }
            } else {
              if (isDebitLeg && t.type == 'DEBIT') {
                calculatedBalance -= t.amount;
              } else if (isDebitLeg && t.type == 'CREDIT') {
                calculatedBalance += t.amount;
              } else if (t.isTransfer || t.categoryId == 'Self Transfer') {
                if (isDebitLeg && t.type == 'DEBIT') {
                  calculatedBalance -= t.amount;
                } else if (isCreditLeg || (isDebitLeg && t.type == 'CREDIT')) {
                  calculatedBalance += t.amount;
                }
              }
            }
          }
        }
      } else {
        double totalInflow = 0.0;
        double totalOutflow = 0.0;
        for (final t in recentTransactions) {
          final isThisAcc =
              (t.accountMask?.contains(last4) ?? false) ||
              t.accountId.contains(last4);
          final isCounterpart =
              (t.transferCounterpartMask?.contains(last4) ?? false);

          if (isThisAcc) {
            if (t.type == 'DEBIT') totalOutflow += t.amount;
            if (t.type == 'CREDIT') totalInflow += t.amount;
          }
          if (isCounterpart &&
              (t.isTransfer || t.categoryId == 'Self Transfer')) {
            if (t.type == 'DEBIT') totalInflow += t.amount;
          }
        }
        calculatedBalance = acc.isCreditCard
            ? totalOutflow - totalInflow
            : (acc.currentBalance > 0
                  ? acc.currentBalance + totalInflow - totalOutflow
                  : totalInflow - totalOutflow);
      }

      accounts[i] = acc.copyWith(
        currentBalance: calculatedBalance,
        anchorBalance: anchorBal ?? acc.anchorBalance,
        anchorDate: anchorDate ?? acc.anchorDate,
      );
    }
  }

  @override
  void dispose() {
    AuthService().removeListener(_onAuthStateChanged);
    syncService.removeListener(_onSyncStateChanged);
    syncService.onSyncEvent = null;
    syncService.onReconnected = null;
    AutoScanSchedulerService().removeListener(_onSchedulerStateChanged);
    peerDebtState.removeListener(_onStateChange);
    WidgetsBinding.instance.removeObserver(this);
    _smsRetryTimer?.cancel();
    super.dispose();
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  void _onSyncStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _recoverFromSync() async {
    if (AuthService().isAuthenticated) await _loadPersistentState();
  }

  void _run30DayBackfillScan() async {
    setState(() {
      isScanning30Days = true;
    });

    final now = DateTime.now();

    if (!kIsWeb) {
      List<Map<String, dynamic>> deviceSmsList = [];
      try {
        deviceSmsList = await SmsReceiverService.readPast30DaysSms();
      } catch (_) {}

      if (deviceSmsList.isNotEmpty) {
        int importedCount = 0;
        final Set<String> discoveredAccounts = {};

        for (final sms in deviceSmsList) {
          final parsed = SmsReceiverService.parseSmsBody(
            sms['body'] ?? '',
            sms['sender'] ?? 'BANK',
            DateTime.fromMillisecondsSinceEpoch(
              sms['timestamp'] ?? now.millisecondsSinceEpoch,
            ),
          );
          if (parsed != null) {
            final String last4 = parsed['lastFour'];
            final String bankName = parsed['bankName'] ?? parsed['sender'];
            final double amt = parsed['amount'];
            final String type = parsed['type'];
            final String merchant = parsed['merchant'];
            final String cat = parsed['category'] ?? 'General Expenses';
            final DateTime dt = parsed['timestamp'];

            final String accId = 'acc-real-$last4';
            if (!accounts.any((a) => a.lastFourDigits == last4)) {
              accounts.add(
                FinancialAccount(
                  id: accId,
                  name: '$bankName A/C',
                  type: 'SAVINGS',
                  lastFourDigits: last4,
                  currency: 'INR',
                  currentBalance: 0.0,
                ),
              );
              discoveredAccounts.add('$bankName (**$last4)');
            }

            final String txnId =
                'txn-sms-${dt.millisecondsSinceEpoch}-$importedCount';
            if (!recentTransactions.any((t) => t.id == txnId)) {
              recentTransactions.add(
                TransactionItem(
                  id: txnId,
                  amount: amt,
                  currency: 'INR',
                  type: type,
                  merchantName: merchant,
                  accountId: accId,
                  categoryId: cat,
                  ingestionSource: 'SMS',
                  reconciliationStatus: 'CONFIRMED',
                  timestamp: dt,
                ),
              );
              importedCount++;
            }
          }
        }

        recentTransactions.sort((a, b) => b.timestamp.compareTo(a.timestamp));

        categoryTotals.clear();
        for (final t in recentTransactions) {
          if (t.type == 'DEBIT') {
            final cat = t.categoryId ?? 'General Expenses';
            categoryTotals[cat] = (categoryTotals[cat] ?? 0.0) + t.amount;
          }
        }

        setState(() {
          isScanning30Days = false;
          isHistoricalBackfilled = true;
          lastBackfillScanTime = now;
        });
        _savePersistentState(true, now);

        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: const Row(
                children: [
                  Icon(
                    Icons.mark_email_read,
                    color: AppColors.success,
                    size: 22,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'SMS Ingestion Complete',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Scanned ${deviceSmsList.length} bank SMS notifications from your phone:',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '• $importedCount Transactions Imported',
                    style: const TextStyle(
                      color: AppColors.infoLight,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '• ${discoveredAccounts.length} Accounts Mapped: ${discoveredAccounts.join(", ")}',
                    style: const TextStyle(color: AppColors.infoLight),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text(
                    'View Dashboard',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          );
        }
        return;
      }
    }

    await Future.delayed(const Duration(milliseconds: 600));

    setState(() {
      isScanning30Days = false;
      isHistoricalBackfilled = true;
      lastBackfillScanTime = now;
    });

    _savePersistentState(true, now);

    if (mounted) {
      _showWebEmailScanDialog(now);
    }
  }

  void _showWebEmailScanDialog(DateTime scanTime) {
    final auth = AuthService();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(
              Icons.mark_email_read_outlined,
              color: AppColors.infoLight,
              size: 24,
            ),
            SizedBox(width: 10),
            Text(
              '30-Day Financial Scan (Web)',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.account_circle,
                    color: AppColors.primaryLight,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Linked Account: ${auth.userEmail}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'On desktop web, 30-day scans connect to your linked financial email alerts and e-statements via AWS SNS webhooks:',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 8),
            const Text(
              '• Bank debit & credit alerts (HDFC, SBI, ICICI, Axis, etc.)',
              style: TextStyle(color: AppColors.infoLight, fontSize: 12),
            ),
            const Text(
              '• Credit card itemized monthly e-statements',
              style: TextStyle(color: AppColors.infoLight, fontSize: 12),
            ),
            const Text(
              '• Direct SMS / Statement text paste parser',
              style: TextStyle(color: AppColors.infoLight, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const EmailSettingsScreen(),
                ),
              );
            },
            child: const Text(
              'Email Settings',
              style: TextStyle(color: AppColors.primaryLight),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _showImportSmsStatementDialog();
            },
            child: const Text(
              'Paste Text',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              Navigator.of(ctx).pop();
              _triggerFinancialEmailScan();
            },
            child: const Text(
              'Scan Linked Email',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runIncrementalScanSinceLastScan() async {
    final auth = AuthService();
    if (!auth.hasGmailAccess) {
      final granted = await auth.requestGmailAccess();
      if (!granted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Gmail read permission is required to scan your inbox.',
            ),
            backgroundColor: AppColors.warning,
          ),
        );
        return;
      }
    }

    if (!auth.hasGmailAccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Gmail read permission is required to scan your inbox.',
          ),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final DateTime sinceTime =
        lastBackfillScanTime ??
        AutoScanSchedulerService().lastScanTime ??
        DateTime.now().subtract(const Duration(hours: 24));

    // Subtract 5 minutes buffer so no borderline emails are missed
    final bufferTime = sinceTime.subtract(const Duration(minutes: 5));
    final afterSec = (bufferTime.millisecondsSinceEpoch / 1000).floor();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Checking transactions since ${_formatFriendlyTime(sinceTime)}…',
        ),
        backgroundColor: AppColors.infoLight,
        duration: const Duration(seconds: 2),
      ),
    );

    await _triggerFinancialEmailScan(
      afterTimestamp: afterSec,
      isScheduledScan: false,
    );
  }

  String _formatFriendlyTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }

  Future<PhaseScanAudit?> _runDeveloperPhaseScan(
    int phaseIndex,
    int afterSec,
    int beforeSec,
  ) async {
    final auth = AuthService();
    final userId = auth.currentUser?.id;
    if (userId == null || !auth.hasGmailAccess) {
      final granted = await auth.requestGmailAccess();
      if (granted && auth.currentUser?.id != null) {
        return _runDeveloperPhaseScan(phaseIndex, afterSec, beforeSec);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Gmail read permission is required to run a Phase Audit scan.',
          ),
          backgroundColor: AppColors.warning,
        ),
      );
      return null;
    }

    setState(() {
      isScanning30Days = true;
    });

    try {
      final devService = DeveloperModeService();
      final phaseTitle = 'Phase $phaseIndex';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Scanning all emails for $phaseTitle…'),
          backgroundColor: AppColors.infoLight,
          duration: const Duration(seconds: 2),
        ),
      );

      final result = await GmailScanService().scanInbox(
        afterTimestamp: afterSec,
        beforeTimestamp: beforeSec,
      );
      if (!_isCurrentAuthenticatedUser(userId)) return null;

      if (!result.success) {
        if (mounted) {
          final isAuthErr =
              (result.error ?? '').toLowerCase().contains('invalid') ||
              (result.error ?? '').toLowerCase().contains('credential') ||
              (result.error ?? '').toLowerCase().contains('authorization');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isAuthErr
                    ? 'Gmail session expired. Tap Reconnect to refresh credentials.'
                    : (result.error ?? 'Phase scan failed.'),
              ),
              backgroundColor: AppColors.danger,
              duration: const Duration(seconds: 8),
              action: isAuthErr
                  ? SnackBarAction(
                      label: 'Reconnect',
                      textColor: Colors.white,
                      onPressed: () async {
                        final ok = await AuthService().requestGmailAccess();
                        if (ok && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Reconnected to Gmail! Try running Phase Scan again.',
                              ),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      },
                    )
                  : null,
            ),
          );
        }
        return null;
      }

      int autoAccountedCount = 0;
      int needsReviewCount = 0;
      final List<PhaseAuditItem> items = [];

      final prefs = await SharedPreferences.getInstance();
      if (!_isCurrentAuthenticatedUser(userId)) return null;
      final blacklist =
          (prefs.getStringList('saved_promotional_blacklist') ?? [])
              .map((e) => e.toLowerCase())
              .toList();
      await EntityService().ensureLoaded();
      if (!_isCurrentAuthenticatedUser(userId)) return null;

      // Index candidates by messageId for O(1) lookup
      final candidateMap = <String, Map<String, dynamic>>{};
      for (final c in result.transactionCandidates) {
        final mid = c['messageId'] as String? ?? '';
        if (mid.isNotEmpty) candidateMap[mid] = c;
      }

      // Process each raw email
      for (final raw in result.rawScannedEmails) {
        final msgId = raw['messageId'] as String? ?? '';
        final subject = raw['subject'] as String? ?? '';
        final from = raw['from'] as String? ?? '';
        final date = raw['date'] as String? ?? '';
        final snippet = raw['snippet'] as String? ?? '';

        final candidate = candidateMap[msgId];
        final isCandidate = candidate != null;

        String? status;
        double? amount;
        String? merchantName;
        String? category;
        String? upiId;
        String? upiRef;

        if (isCandidate) {
          amount = (candidate['amount'] as num?)?.toDouble();
          merchantName = candidate['merchantName'] as String?;
          category = candidate['category'] as String?;
          upiId = candidate['upiId'] as String?;
          upiRef = candidate['referenceNumber'] as String?;
          final accountMask = candidate['accountMask'] as String?;
          final cleanMerchant = merchantName?.trim();
          final stableTxnId = 'txn-gmail-$msgId';

          final fullText = '${cleanMerchant ?? ''} $subject $snippet'
              .toLowerCase();
          final isBlacklisted = blacklist.any((w) => fullText.contains(w));

          if (isBlacklisted) {
            status = 'PROMOTIONAL';
          } else if (_isDueOrBillNotice(fullText)) {
            status = 'BILL_DUE_REMINDER';
          } else {
            final alreadyInLedger = recentTransactions.any(
              (t) =>
                  t.id == stableTxnId ||
                  (upiRef != null &&
                      upiRef.isNotEmpty &&
                      t.referenceNumber == upiRef),
            );
            final alreadyPending = pendingTransactions.any(
              (t) =>
                  t.id == stableTxnId ||
                  (upiRef != null &&
                      upiRef.isNotEmpty &&
                      t.referenceNumber == upiRef),
            );

            if (alreadyInLedger) {
              status = 'ALREADY_IN_LEDGER';
            } else if (alreadyPending) {
              status = 'NEEDS_REVIEW';
              needsReviewCount++;
            } else {
              DateTime txDate = DateTime.now();
              if (candidate['date'] != null) {
                try {
                  txDate = DateTime.parse(candidate['date']);
                } catch (_) {}
              }

              final matchedEntity = EntityService().matchEntity(
                rawName: cleanMerchant ?? '',
                upiId: upiId,
                accountMask: accountMask,
              );

              if (matchedEntity != null) {
                status = 'AUTO_CONFIRMED';
                merchantName = matchedEntity.name;
                category = matchedEntity.defaultCategory ?? 'General Expenses';
                final autoTxn = TransactionItem(
                  id: stableTxnId,
                  amount: amount ?? 0.0,
                  currency: 'INR',
                  type: candidate['type'] as String? ?? 'DEBIT',
                  merchantName: matchedEntity.name,
                  accountId: 'acc-gmail',
                  categoryId: category,
                  subCategory: matchedEntity.defaultSubCategory,
                  ingestionSource: 'EMAIL',
                  reconciliationStatus: 'AUTO_CONFIRMED',
                  timestamp: txDate,
                  accountMask: accountMask,
                  referenceNumber: upiRef,
                  rawSnippet: snippet,
                );
                _addConfirmedTransaction(autoTxn);
                if (autoTxn.type == 'DEBIT') {
                  final String finalCat = category;
                  categoryTotals[finalCat] =
                      (categoryTotals[finalCat] ?? 0.0) + autoTxn.amount;
                }
                if (AuthService().isAuthenticated) {
                  BackendApiService().createTransaction(autoTxn);
                }
                autoAccountedCount++;
              } else {
                status = 'NEEDS_REVIEW';
                needsReviewCount++;
                pendingTransactions.add(
                  TransactionItem(
                    id: stableTxnId,
                    amount: amount ?? 0.0,
                    currency: 'INR',
                    type: candidate['type'] as String? ?? 'DEBIT',
                    merchantName: cleanMerchant ?? 'Unknown Merchant',
                    accountId: 'acc-gmail',
                    categoryId: category ?? 'General Expenses',
                    ingestionSource: 'EMAIL',
                    reconciliationStatus: 'NEEDS_REVIEW',
                    timestamp: txDate,
                    accountMask: accountMask,
                    referenceNumber: upiRef,
                    rawSnippet: snippet,
                  ),
                );
                pendingTransactions.sort(
                  (a, b) => b.timestamp.compareTo(a.timestamp),
                );
              }
            }
          }
        } else {
          status = 'IGNORED';
        }

        items.add(
          PhaseAuditItem(
            messageId: msgId,
            subject: subject,
            from: from,
            date: date,
            snippet: snippet,
            isCandidate: isCandidate,
            amount: amount,
            merchantName: merchantName,
            category: category,
            upiId: upiId,
            upiRef: upiRef,
            status: status,
          ),
        );
      }

      final audit = PhaseScanAudit(
        phaseIndex: phaseIndex,
        phaseTitle: phaseTitle,
        scannedAt: DateTime.now(),
        emailsScanned: result.emailsScanned,
        candidatesCount: result.transactionCandidates.length,
        autoAccountedCount: autoAccountedCount,
        needsReviewCount: needsReviewCount,
        items: items,
      );

      devService.recordPhaseAudit(audit);

      _reconcileSelfTransfers();
      setState(() {
        isHistoricalBackfilled = true;
        lastBackfillScanTime = DateTime.now();
      });
      await _savePersistentState(true, DateTime.now(), expectedUserId: userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Phase $phaseIndex Audit Complete: ${result.emailsScanned} emails scanned, ${result.transactionCandidates.length} txns found ($autoAccountedCount auto-accounted)',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }

      return audit;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Phase scan error: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
      return null;
    } finally {
      if (mounted) {
        setState(() {
          isScanning30Days = false;
        });
      }
    }
  }

  Future<void> _triggerFinancialEmailScan({
    int? afterTimestamp,
    int? beforeTimestamp,
    bool isScheduledScan = false,
  }) async {
    final auth = AuthService();
    final userId = auth.currentUser?.id;
    if (userId == null || !auth.hasGmailAccess) {
      if (!isScheduledScan) {
        final granted = await auth.requestGmailAccess();
        if (granted) {
          await _triggerFinancialEmailScan(
            afterTimestamp: afterTimestamp,
            beforeTimestamp: beforeTimestamp,
            isScheduledScan: false,
          );
          return;
        }
      }
      if (!isScheduledScan) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Gmail read permission is required to scan your inbox.',
            ),
            backgroundColor: AppColors.warning,
          ),
        );
      }
      return;
    }

    if (!isScheduledScan) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Scanning Gmail inbox for bank alerts & statements…'),
          backgroundColor: AppColors.infoLight,
          duration: Duration(seconds: 2),
        ),
      );
    }

    try {
      final result = await GmailScanService().scanInbox(
        afterTimestamp: afterTimestamp,
        beforeTimestamp: beforeTimestamp,
      );
      if (!mounted || !_isCurrentAuthenticatedUser(userId)) return;
      if (!result.success) {
        if (!isScheduledScan) {
          final isAuthErr =
              (result.error ?? '').toLowerCase().contains('invalid') ||
              (result.error ?? '').toLowerCase().contains('credential') ||
              (result.error ?? '').toLowerCase().contains('authorization');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isAuthErr
                    ? 'Gmail session expired. Tap Reconnect to refresh credentials.'
                    : (result.error ?? 'Gmail scan failed. Please try again.'),
              ),
              backgroundColor: AppColors.danger,
              duration: const Duration(seconds: 8),
              action: isAuthErr
                  ? SnackBarAction(
                      label: 'Reconnect',
                      textColor: Colors.white,
                      onPressed: () async {
                        final ok = await AuthService().requestGmailAccess();
                        if (ok && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Reconnected to Gmail! Try scanning again.',
                              ),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      },
                    )
                  : null,
            ),
          );
        }
        return;
      }

      int autoAccountedCount = 0;

      if (result.transactionCandidates.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        if (!_isCurrentAuthenticatedUser(userId)) return;
        final blacklist =
            (prefs.getStringList('saved_promotional_blacklist') ?? [])
                .map((e) => e.toLowerCase())
                .toList();
        await EntityService().ensureLoaded();
        if (!_isCurrentAuthenticatedUser(userId)) return;

        for (final candidate in result.transactionCandidates) {
          final cleanMerchant = (candidate['merchantName'] as String?)?.trim();
          final subject = (candidate['subject'] as String?)?.trim();
          final snippet = (candidate['snippet'] as String?)?.trim();
          final fullText =
              '${cleanMerchant ?? ''} ${subject ?? ''} ${snippet ?? ''}'
                  .toLowerCase();

          // Skip if matches user's promotional blacklist
          if (blacklist.any((b) => b.isNotEmpty && fullText.contains(b))) {
            continue;
          }
          // Skip if email is a bill due or statement reminder
          if (_isDueOrBillNotice(fullText)) {
            continue;
          }
          // Strict client-side filter for promo cashback hooks
          if ((fullText.contains('cashback') && fullText.contains('win')) ||
              fullText.contains('chance to win') ||
              fullText.contains('fastag 🚗') ||
              fullText.contains('#paytmkaro')) {
            continue;
          }

          final msgId = (candidate['messageId'] as String?)?.trim();
          final stableTxnId = (msgId != null && msgId.isNotEmpty)
              ? 'txn-gmail-$msgId'
              : 'txn-gmail-${DateTime.now().millisecondsSinceEpoch}';

          final snippetText = candidate['snippet'] as String? ?? '';
          DateTime txDate =
              DateTime.tryParse(candidate['date'] as String? ?? '') ??
              DateTime.now();
          final dateMatch = RegExp(
            r'\bon\s+(\d{1,2})[-/](\d{1,2})[-/](\d{2,4})\b',
            caseSensitive: false,
          ).firstMatch(snippetText);
          if (dateMatch != null) {
            try {
              final d = int.parse(dateMatch.group(1)!);
              final m = int.parse(dateMatch.group(2)!);
              var y = int.parse(dateMatch.group(3)!);
              if (y < 100) y += 2000;
              txDate = DateTime(y, m, d, txDate.hour, txDate.minute);
            } catch (_) {}
          }

          // Extract UPI reference number if available in snippet
          String? upiRef = candidate['upiId'] as String?;
          final refMatch = RegExp(
            r'(?:UPI\s*(?:trans(?:action)?\s*)?ref(?:erence)?(?:\s*no\.?)?|UTR(?:\s*no\.?)?|Ref(?:\s*no\.?)?|RRN)[:\s]+([0-9]{8,18})',
            caseSensitive: false,
          ).firstMatch(snippetText);
          if (refMatch != null && refMatch.group(1) != null) {
            upiRef = refMatch.group(1);
          }

          // 1. Skip if ALREADY in pending
          final alreadyPending = pendingTransactions.any(
            (t) =>
                t.id == stableTxnId ||
                (msgId != null && msgId.isNotEmpty && t.id.contains(msgId)),
          );
          if (alreadyPending) continue;

          // 2. Skip if ALREADY confirmed in recent transactions
          final alreadyConfirmed = recentTransactions.any(
            (t) =>
                t.id == stableTxnId ||
                (msgId != null && msgId.isNotEmpty && t.id.contains(msgId)) ||
                (upiRef != null &&
                    upiRef.isNotEmpty &&
                    t.referenceNumber == upiRef),
          );
          if (alreadyConfirmed) continue;

          final merchantToUse =
              (cleanMerchant != null &&
                  cleanMerchant.isNotEmpty &&
                  cleanMerchant != 'Bank Alert')
              ? cleanMerchant
              : (subject != null && subject.isNotEmpty
                    ? subject
                    : 'Email Transaction');

          final accountMask = candidate['accountMask'] as String?;

          // Auto-discover account card if not yet registered
          if (accountMask != null && accountMask.isNotEmpty) {
            final digits = accountMask.replaceAll(RegExp(r'[^0-9]'), '');
            final last4 = digits.length >= 4
                ? digits.substring(digits.length - 4)
                : accountMask;
            final exists = accounts.any(
              (a) => a.lastFourDigits == last4 || a.id == 'acc-$last4',
            );
            if (!exists) {
              final newAcc = FinancialAccount(
                id: 'acc-$last4',
                name: 'HDFC Bank (•••• $last4)',
                type: 'SAVINGS',
                lastFourDigits: last4,
                currentBalance: 0.0,
                currency: 'INR',
              );
              accounts.add(newAcc);
              if (_isCurrentAuthenticatedUser(userId)) {
                BackendApiService().createAccount(newAcc);
              }
            }
          }

          // Check if merchant or UPI ID matches an existing alias entity!
          final matchedEntity = EntityService().matchEntity(
            upiId: candidate['upiId'] as String?,
            rawName: cleanMerchant ?? merchantToUse,
            accountMask: accountMask,
          );

          if (matchedEntity != null) {
            // AUTOMATICALLY ACCOUNTED FOR — NO REVIEW NEEDED!
            final autoTxn = TransactionItem(
              id: stableTxnId,
              amount: (candidate['amount'] as num?)?.toDouble() ?? 0.0,
              currency: 'INR',
              type: candidate['type'] as String? ?? 'DEBIT',
              merchantName: matchedEntity.name,
              accountId: 'acc-gmail',
              categoryId: matchedEntity.defaultCategory ?? 'General Expenses',
              subCategory: matchedEntity.defaultSubCategory,
              ingestionSource: 'EMAIL',
              reconciliationStatus: 'AUTO_CONFIRMED',
              timestamp: txDate,
              accountMask: accountMask,
              referenceNumber: upiRef,
              rawSnippet: candidate['snippet'] as String?,
            );

            _addConfirmedTransaction(autoTxn);
            if (autoTxn.type == 'DEBIT') {
              final cat = autoTxn.categoryId ?? 'General Expenses';
              categoryTotals[cat] =
                  (categoryTotals[cat] ?? 0.0) + autoTxn.amount;
            }
            if (_isCurrentAuthenticatedUser(userId)) {
              BackendApiService().createTransaction(autoTxn);
            }
            autoAccountedCount++;
            continue; // Skip putting into pendingTransactions!
          }

          // Unknown merchant: queue for user review
          pendingTransactions.add(
            TransactionItem(
              id: stableTxnId,
              amount: (candidate['amount'] as num?)?.toDouble() ?? 0.0,
              currency: 'INR',
              type: candidate['type'] as String? ?? 'DEBIT',
              merchantName: merchantToUse,
              accountId: 'acc-gmail',
              categoryId:
                  candidate['category'] as String? ?? 'General Expenses',
              ingestionSource: 'EMAIL',
              reconciliationStatus: 'NEEDS_REVIEW',
              timestamp: txDate,
              accountMask: accountMask,
              referenceNumber: upiRef,
              rawSnippet: candidate['snippet'] as String?,
            ),
          );
        }

        _reconcileSelfTransfers();
        setState(() {
          isHistoricalBackfilled = true;
          lastBackfillScanTime = DateTime.now();
        });
        await _savePersistentState(
          isHistoricalBackfilled,
          lastBackfillScanTime ?? DateTime.now(),
          expectedUserId: userId,
        );
      }

      if (!mounted || !_isCurrentAuthenticatedUser(userId)) return;
      final autoMsg = autoAccountedCount > 0
          ? ' ($autoAccountedCount auto-accounted via merchant alias)'
          : '';
      final reviewMsg = pendingTransactions.isNotEmpty
          ? 'Tap Review to confirm remaining.'
          : (autoAccountedCount > 0 ? 'All transactions accounted for!' : '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${result.message}$autoMsg. $reviewMsg'.trim()),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gmail scan error. Check your connection.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  /// Real Google OAuth sign-in — triggers the browser consent popup.
  Future<void> _signInWithGoogle() async {
    final auth = AuthService();
    final success = await auth.signInWithGoogle();
    if (!mounted) return;
    if (success) {
      setState(() {});
      await _loadPersistentState();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Signed in as ${auth.displayName} (${auth.userEmail})',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } else {
      final errorMsg =
          auth.lastError ?? 'Sign-in cancelled or failed. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: AppColors.danger,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  // Keep old name as alias so other callers don't break
  void _showGoogleOAuthDialog() => _signInWithGoogle();

  void _showUserProfileDialog() {
    final auth = AuthService();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              auth.photoUrl != null
                  ? CircleAvatar(
                      radius: 20,
                      backgroundImage: NetworkImage(auth.photoUrl!),
                    )
                  : CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.primary,
                      child: Text(
                        auth.displayName.isNotEmpty
                            ? auth.displayName[0].toUpperCase()
                            : 'U',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      auth.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      auth.userEmail,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.verified_user,
                          color: Color(0xFF4285F4),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'Verified Google Identity',
                            style: TextStyle(
                              color: Color(0xFF93C5FD),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: auth.hasGmailAccess
                                ? const Color(0x2210B981)
                                : const Color(0x22F59E0B),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                auth.hasGmailAccess
                                    ? Icons.mark_email_read
                                    : Icons.email_outlined,
                                size: 11,
                                color: auth.hasGmailAccess
                                    ? AppColors.success
                                    : AppColors.warning,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                auth.hasGmailAccess ? 'Gmail ✓' : 'Gmail —',
                                style: TextStyle(
                                  color: auth.hasGmailAccess
                                      ? AppColors.success
                                      : AppColors.warning,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      auth.hasGmailAccess
                          ? 'gmail.readonly granted — inbox scanning active'
                          : 'gmail.readonly not yet granted',
                      style: TextStyle(
                        color: auth.hasGmailAccess
                            ? AppColors.textSecondary
                            : AppColors.warning,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (!auth.hasGmailAccess) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.warning),
                      foregroundColor: AppColors.warning,
                    ),
                    icon: const Icon(Icons.mail_outline, size: 16),
                    label: const Text(
                      'Grant Gmail Access',
                      style: TextStyle(fontSize: 13),
                    ),
                    onPressed: () async {
                      final granted = await auth.requestGmailAccess();
                      setDialogState(() {});
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              granted
                                  ? 'Gmail access granted! Inbox scanning enabled.'
                                  : 'Gmail access not granted.',
                            ),
                            backgroundColor: granted
                                ? AppColors.success
                                : AppColors.danger,
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await auth.signOut();
                if (mounted) {
                  setState(() {
                    accounts.clear();
                    recentTransactions.clear();
                    pendingTransactions.clear();
                    categoryTotals.clear();
                    isHistoricalBackfilled = false;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Signed out. Your data is safely stored in the cloud.',
                      ),
                      backgroundColor: AppColors.textMuted,
                    ),
                  );
                }
              },
              child: const Text(
                'Sign Out',
                style: TextStyle(color: AppColors.dangerLight),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Done', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _openReviewModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TransactionReviewModal(
        pendingTransactions: pendingTransactions,
        existingTransactions: recentTransactions,
        existingAccounts: accounts,
        confirmationErrorMessage: () =>
            BackendApiService().lastTransactionError,
        onCreateLoanAccount: (newAcc) async {
          setState(() {
            accounts.removeWhere(
              (a) =>
                  a.id == newAcc.id ||
                  (a.type == 'LOAN' &&
                      a.lastFourDigits == newAcc.lastFourDigits),
            );
            accounts.add(newAcc);
          });
          await _savePersistentState(
            isHistoricalBackfilled,
            lastBackfillScanTime ?? DateTime.now(),
          );
          if (AuthService().isAuthenticated) {
            BackendApiService().createAccount(newAcc);
          }
        },
        onConfirm: (txn, category) async {
          final isExcluded = category == 'Not Applicable / Exclude';
          var confirmedTxn = txn.copyWith(
            categoryId: category,
            reconciliationStatus: isExcluded ? 'EXCLUDED' : 'CONFIRMED',
          );
          final persisted =
              await (widget.onReviewConfirmation?.call(confirmedTxn) ??
                  (txn.potentialDuplicateOfTransactionId != null
                      ? BackendApiService().confirmReconciledTransaction(
                          confirmedTxn,
                        )
                      : _confirmReviewedTransaction(confirmedTxn)));
          if (persisted == null || !mounted) {
            return false;
          }
          confirmedTxn = persisted;

          setState(() {
            pendingTransactions.removeWhere((t) => t.id == txn.id);
            _addConfirmedTransaction(confirmedTxn);
            if (confirmedTxn.isTransfer || category == 'Self Transfer') {
              _reconcileSelfTransfers();
            }
            if (txn.type == 'DEBIT' &&
                !isExcluded &&
                !confirmedTxn.isTransfer) {
              categoryTotals[category] =
                  (categoryTotals[category] ?? 0.0) + confirmedTxn.amount;
            }
          });
          _savePersistentState(
            isHistoricalBackfilled,
            lastBackfillScanTime ?? DateTime.now(),
          );

          ScaffoldMessenger.of(this.context).showSnackBar(
            SnackBar(
              content: Text(
                isExcluded
                    ? 'Marked as Excluded from personal finances'
                    : (confirmedTxn.isTransfer
                          ? '🔁 Confirmed Self-Transfer: ₹${confirmedTxn.amount.toStringAsFixed(2)} (${confirmedTxn.merchantName})'
                          : 'Confirmed ₹${confirmedTxn.amount.toStringAsFixed(2)} to ${confirmedTxn.merchantName} ($category${confirmedTxn.subCategory != null && confirmedTxn.subCategory!.isNotEmpty ? " › ${confirmedTxn.subCategory}" : ""})'),
              ),
              backgroundColor: isExcluded
                  ? const Color(0xFFF97316)
                  : (confirmedTxn.isTransfer
                        ? const Color(0xFF0891B2)
                        : AppColors.success),
            ),
          );
          return true;
        },
        onMerge: (target, duplicate) async {
          final persisted = await BackendApiService().mergeReconciledDuplicate(
            canonicalTransactionId: target.id,
            duplicateTransactionId: duplicate.id,
          );
          if (persisted == null || !mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Unable to merge this review. Please try again.'),
                backgroundColor: AppColors.danger,
              ),
            );
            return;
          }
          final isExcluded = target.categoryId == 'Not Applicable / Exclude';
          final mergedTxn = persisted;
          final canonicalWasAlreadyCounted = recentTransactions.any(
            (item) => item.id == target.id,
          );
          setState(() {
            pendingTransactions.removeWhere(
              (t) => t.id == target.id || t.id == duplicate.id,
            );
            _addConfirmedTransaction(mergedTxn);
            if (mergedTxn.type == 'DEBIT' &&
                !isExcluded &&
                !canonicalWasAlreadyCounted) {
              categoryTotals[mergedTxn.categoryId ?? 'General Expenses'] =
                  (categoryTotals[mergedTxn.categoryId ?? 'General Expenses'] ??
                      0.0) +
                  mergedTxn.amount;
            }
          });
          _savePersistentState(
            isHistoricalBackfilled,
            lastBackfillScanTime ?? DateTime.now(),
          );

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Merged duplicate alerts into 1 confirmed expense: ₹${target.amount.toStringAsFixed(2)} to ${target.merchantName}',
              ),
              backgroundColor: AppColors.success,
            ),
          );
        },
        onDismiss: (txn) {
          setState(() {
            pendingTransactions.removeWhere((t) => t.id == txn.id);
          });
          _savePersistentState(
            isHistoricalBackfilled,
            lastBackfillScanTime ?? DateTime.now(),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Transaction dismissed'),
              backgroundColor: AppColors.textMuted,
              duration: Duration(seconds: 2),
            ),
          );
        },
        onMarkPromotional: (txn) async {
          final userId = AuthService().currentUser?.id;
          if (userId == null) return;
          setState(() {
            pendingTransactions.removeWhere((t) => t.id == txn.id);
          });
          final pattern = txn.merchantName.trim();
          try {
            final prefs = await SharedPreferences.getInstance();
            if (!_isCurrentAuthenticatedUser(userId)) return;
            final currentBlacklist =
                prefs.getStringList('saved_promotional_blacklist') ?? [];
            if (pattern.isNotEmpty &&
                !currentBlacklist.contains(pattern.toLowerCase())) {
              currentBlacklist.add(pattern.toLowerCase());
              await prefs.setStringList(
                'saved_promotional_blacklist',
                currentBlacklist,
              );
            }
          } catch (_) {}
          _savePersistentState(
            isHistoricalBackfilled,
            lastBackfillScanTime ?? DateTime.now(),
            expectedUserId: userId,
          );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Marked as Promotional. Pattern added to spam filter.',
                ),
                backgroundColor: const Color(0xFFF97316),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        },
        onPurgeInvalid: () {
          final removed = pendingTransactions
              .where((t) => t.amount <= 0)
              .length;
          setState(() {
            pendingTransactions.removeWhere((t) => t.amount <= 0);
          });
          _savePersistentState(
            isHistoricalBackfilled,
            lastBackfillScanTime ?? DateTime.now(),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Purged $removed promo / invalid items!'),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
    );
  }

  Future<TransactionItem?> _confirmReviewedTransaction(
    TransactionItem transaction,
  ) {
    if (!AuthService().isAuthenticated) {
      return Future<TransactionItem?>.value(null);
    }
    return BackendApiService().confirmReviewedTransaction(transaction);
  }

  void _openSplitModal(TransactionItem txn) {
    showDialog(
      context: context,
      builder: (context) => SplitExpenseModal(
        transaction: txn,
        onCompleted: () => setState(() {}),
      ),
    );
  }

  // Calculate Net Aggregate Balance & Financial Health Metrics
  double get _totalLiquidBalance {
    double sum = 0.0;
    for (final acc in accounts) {
      if (acc.isSavings) {
        sum += acc.currentBalance;
      }
    }
    return sum;
  }

  double get _totalMonthlySpend {
    double sum = 0.0;
    for (final t in recentTransactions) {
      if (t.reconciliationStatus == 'EXCLUDED' ||
          t.categoryId == 'Not Applicable / Exclude' ||
          t.isTransfer ||
          t.categoryId == 'Self Transfer' ||
          t.categoryId == 'Transfer' ||
          t.type == 'TRANSFER')
        continue;
      if (t.type == 'DEBIT') sum += t.effectivePersonalExpense;
    }
    return sum;
  }

  double get _totalMonthlyIncome {
    double sum = 0.0;
    for (final t in recentTransactions) {
      if (t.reconciliationStatus == 'EXCLUDED' ||
          t.categoryId == 'Not Applicable / Exclude' ||
          t.isTransfer ||
          t.categoryId == 'Self Transfer' ||
          t.categoryId == 'Transfer' ||
          t.type == 'TRANSFER')
        continue;
      if (t.type == 'CREDIT') sum += t.amount;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final summaries = peerDebtState.contactSummaries;
    double totalOwedToMe = 0.0;
    for (final s in summaries) {
      if (s.netBalance > 0) totalOwedToMe += s.netBalance;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildModernAppBar(context),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWideScreen = constraints.maxWidth > 900;
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isWideScreen ? 32.0 : 16.0,
              vertical: 20.0,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1400),
                child: isWideScreen
                    ? _buildWideScreenLayout(context, totalOwedToMe, summaries)
                    : _buildMobileLayout(context, totalOwedToMe, summaries),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddTransactionDialog,
        backgroundColor: AppColors.primary,
        foregroundColor: const Color(0xFF03161D),
        icon: const Icon(Icons.add),
        label: const Text(
          'Add Transaction',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildModernAppBar(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 900;
    final isWideDesktop = screenWidth >= 1800;
    final syncStatus = switch (syncService.state) {
      SyncConnectionState.connected => 'SYNCED',
      SyncConnectionState.connecting ||
      SyncConnectionState.reconnecting => 'RECONNECTING',
      SyncConnectionState.disconnected => 'OFFLINE',
    };
    final syncColor = syncService.isConnected
        ? AppColors.successLight
        : syncService.state == SyncConnectionState.reconnecting ||
              syncService.state == SyncConnectionState.connecting
        ? AppColors.warningLight
        : AppColors.textMuted;

    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      titleSpacing: isDesktop ? 32.0 : 16.0,
      title: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.account_balance_wallet_outlined,
                size: 18,
                color: Color(0xFF03161D),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Expense Tracker',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.white,
                fontSize: 18,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: syncService.isConnected
                    ? const Color(0x2610B981)
                    : const Color(0x26111C2B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: syncColor.withValues(alpha: 0.4),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 6, color: syncColor),
                  const SizedBox(width: 4),
                  Text(
                    'LIVE',
                    style: TextStyle(
                      color: syncColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    syncStatus,
                    style: TextStyle(
                      color: syncColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (isWideDesktop) ...[
          _buildNavButton(
            icon: Icons.people_alt_outlined,
            label: 'Peer Debt',
            color: AppColors.successLight,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const PeerDebtScreen()),
            ),
          ),
          _buildNavButton(
            icon: Icons.account_balance_outlined,
            label: 'Loans & EMI',
            color: AppColors.warningLight,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const LoanTrackingScreen(),
              ),
            ),
          ),
          _buildNavButton(
            icon: Icons.credit_card_outlined,
            label: 'Card EMIs',
            color: AppColors.successLight,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const CardEmiScreen()),
            ),
          ),
          _buildNavButton(
            icon: Icons.receipt_outlined,
            label: 'Bills',
            color: AppColors.dangerLight,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const BillTrackerScreen(),
              ),
            ),
          ),
          _buildNavButton(
            icon: Icons.pie_chart_outline,
            label: 'Budgets',
            color: AppColors.purpleLight,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const BudgetScreen()),
            ),
          ),
          _buildNavButton(
            icon: Icons.payments_outlined,
            label: 'Income',
            color: AppColors.successLight,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const IncomeSourceScreen(),
              ),
            ),
          ),
          _buildNavButton(
            icon: Icons.analytics_outlined,
            label: 'Insights',
            color: AppColors.infoLight,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const AnalyticsScreen()),
            ),
          ),
          _buildNavButton(
            icon: Icons.tune_outlined,
            label: 'Context',
            color: AppColors.purpleLight,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const FinancialContextScreen(),
              ),
            ),
          ),
          _buildNavButton(
            icon: Icons.mark_email_read_outlined,
            label: 'Email Sync',
            color: AppColors.infoLight,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const EmailSettingsScreen(),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ] else ...[
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.grid_view_rounded,
              color: AppColors.textPrimary,
            ),
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppColors.border),
            ),
            tooltip: 'Features & Tools',
            onSelected: (val) {
              switch (val) {
                case 'debt':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const PeerDebtScreen(),
                    ),
                  );
                  break;
                case 'loan':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const LoanTrackingScreen(),
                    ),
                  );
                  break;
                case 'emi':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const CardEmiScreen(),
                    ),
                  );
                  break;
                case 'bills':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const BillTrackerScreen(),
                    ),
                  );
                  break;
                case 'budget':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const BudgetScreen(),
                    ),
                  );
                  break;
                case 'income':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const IncomeSourceScreen(),
                    ),
                  );
                  break;
                case 'analytics':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const AnalyticsScreen(),
                    ),
                  );
                  break;
                case 'context':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const FinancialContextScreen(),
                    ),
                  );
                  break;
                case 'email':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const EmailSettingsScreen(),
                    ),
                  );
                  break;
                case 'dev':
                  DeveloperModeService().toggle();
                  break;
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'dev',
                child: Row(
                  children: [
                    Icon(
                      Icons.developer_mode,
                      color: Color(0xFFA78BFA),
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Toggle Developer Mode',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'debt',
                child: Row(
                  children: [
                    Icon(
                      Icons.people_alt_outlined,
                      color: AppColors.successLight,
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Peer Debt Ledger',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'loan',
                child: Row(
                  children: [
                    Icon(
                      Icons.account_balance_outlined,
                      color: AppColors.warningLight,
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Loan & EMI Tracker',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'emi',
                child: Row(
                  children: [
                    Icon(
                      Icons.credit_card_outlined,
                      color: AppColors.successLight,
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Card EMI Schedules',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'bills',
                child: Row(
                  children: [
                    Icon(
                      Icons.receipt_outlined,
                      color: AppColors.dangerLight,
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Credit Card Bills',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'budget',
                child: Row(
                  children: [
                    Icon(
                      Icons.pie_chart_outline,
                      color: AppColors.purpleLight,
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Monthly Budgets',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'income',
                child: Row(
                  children: [
                    Icon(
                      Icons.payments_outlined,
                      color: AppColors.successLight,
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Income Sources',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'analytics',
                child: Row(
                  children: [
                    Icon(
                      Icons.analytics_outlined,
                      color: AppColors.infoLight,
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Analytics & AI Insights',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'context',
                child: Row(
                  children: [
                    Icon(
                      Icons.tune_outlined,
                      color: AppColors.purpleLight,
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Financial Context',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'email',
                child: Row(
                  children: [
                    Icon(
                      Icons.mark_email_read_outlined,
                      color: AppColors.infoLight,
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Linked Email Accounts',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
        if (screenWidth > 480) ...[
          AnimatedBuilder(
            animation: DeveloperModeService(),
            builder: (context, _) {
              final devService = DeveloperModeService();
              final isDev = devService.isEnabled;
              return InkWell(
                onTap: () {
                  devService.toggle();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Developer Mode ${!isDev ? "Enabled (Audit Panel Active)" : "Disabled"}',
                      ),
                      backgroundColor: !isDev
                          ? AppColors.purple
                          : AppColors.surfaceElevated,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isDev
                        ? const Color(0x338B5CF6)
                        : const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDev
                          ? const Color(0xFFA78BFA)
                          : const Color(0xFF475569),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.developer_mode,
                        size: 14,
                        color: isDev ? const Color(0xFFA78BFA) : Colors.white54,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isDev ? 'DEV ON' : 'DEV OFF',
                        style: TextStyle(
                          color: isDev
                              ? const Color(0xFFA78BFA)
                              : Colors.white60,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
        if (!kIsWeb)
          IconButton(
            icon: const Icon(Icons.lock_outline, color: AppColors.dangerLight),
            tooltip: 'Lock Application',
            onPressed: () => SecurityState().lockApp(),
          ),
        Padding(
          padding: EdgeInsets.only(right: isDesktop ? 32.0 : 16.0),
          child: !AuthService().isAuthenticated
              ? (isDesktop
                    ? ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF0F172A),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 0,
                        ),
                        icon: const Icon(
                          Icons.login,
                          size: 16,
                          color: Color(0xFF4285F4),
                        ),
                        label: const Text(
                          'Sign In',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        onPressed: _showGoogleOAuthDialog,
                      )
                    : IconButton(
                        icon: const Icon(
                          Icons.login,
                          size: 20,
                          color: Color(0xFF4285F4),
                        ),
                        tooltip: 'Sign In',
                        onPressed: _showGoogleOAuthDialog,
                      ))
              : InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _showUserProfileDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: AppColors.primary,
                          child: Text(
                            AuthService().displayName.isNotEmpty
                                ? AuthService().displayName[0].toUpperCase()
                                : 'U',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          AuthService().displayName,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // DESKTOP WIDE SCREEN BENTO GRID LAYOUT (>900px)
  // ==========================================
  Widget _buildWideScreenLayout(
    BuildContext context,
    double totalOwedToMe,
    List<ContactDebtSummary> summaries,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeroAggregateCard(),
        const SizedBox(height: 20),
        DeveloperAuditPanel(
          onRunPhaseScan: _runDeveloperPhaseScan,
          isScanning: isScanning30Days,
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Column (60% width): Accounts & Transactions
            Expanded(
              flex: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAccountsSection(),
                  const SizedBox(height: 24),
                  _buildRecentTransactionsSection(),
                ],
              ),
            ),
            const SizedBox(width: 24),
            // Right Column (40% width): Action Hub, Categories, Debts
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (pendingTransactions.isNotEmpty)
                    UncategorizedReviewBanner(
                      pendingTransactions: pendingTransactions,
                      onReviewPressed: _openReviewModal,
                    ),
                  HistoricalBackfillCard(
                    onScanPressed: isHistoricalBackfilled
                        ? _runIncrementalScanSinceLastScan
                        : _run30DayBackfillScan,
                    isScanning: isScanning30Days,
                    isCompleted: isHistoricalBackfilled,
                    lastScannedAt: lastBackfillScanTime,
                  ),
                  _buildSmsCaptureCard(),
                  _buildAutoSyncScheduleCard(),
                  _buildPeerDebtGlanceCard(context, totalOwedToMe, summaries),
                  CategoryBreakdownView(categoryTotals: categoryTotals),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ==========================================
  // MOBILE / COMPACT SCREEN LAYOUT (<= 900px)
  // ==========================================
  Widget _buildMobileLayout(
    BuildContext context,
    double totalOwedToMe,
    List<ContactDebtSummary> summaries,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeroAggregateCard(),
        const SizedBox(height: 16),
        DeveloperAuditPanel(
          onRunPhaseScan: _runDeveloperPhaseScan,
          isScanning: isScanning30Days,
        ),
        if (pendingTransactions.isNotEmpty)
          UncategorizedReviewBanner(
            pendingTransactions: pendingTransactions,
            onReviewPressed: _openReviewModal,
          ),
        HistoricalBackfillCard(
          onScanPressed: isHistoricalBackfilled
              ? _runIncrementalScanSinceLastScan
              : _run30DayBackfillScan,
          isScanning: isScanning30Days,
          isCompleted: isHistoricalBackfilled,
          lastScannedAt: lastBackfillScanTime,
        ),
        _buildSmsCaptureCard(),
        _buildAutoSyncScheduleCard(),
        _buildPeerDebtGlanceCard(context, totalOwedToMe, summaries),
        const SizedBox(height: 16),
        _buildAccountsSection(),
        const SizedBox(height: 20),
        CategoryBreakdownView(categoryTotals: categoryTotals),
        const SizedBox(height: 20),
        _buildRecentTransactionsSection(),
      ],
    );
  }

  // ==========================================
  // HERO FINANCIAL HEALTH & NET POSITION CARD
  // ==========================================
  Widget _buildSmsCaptureCard() {
    if (kIsWeb) return const SizedBox.shrink();
    final status = _smsCaptureStatus;
    final capturing = status?.isCapturing == true;
    final unavailable = status != null && !status.isSupported;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: capturing
              ? AppColors.success.withValues(alpha: 0.55)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            capturing ? Icons.sms_outlined : Icons.sms_failed_outlined,
            color: capturing ? AppColors.successLight : AppColors.warningLight,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  capturing ? 'SMS capture active' : 'Capture bank SMS alerts',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  unavailable
                      ? 'SMS capture is available only on Android.'
                      : capturing
                      ? 'Parsed transaction fields are queued privately before sync. SMS text is not retained.'
                      : 'Allow SMS alerts to be captured and queued when you are offline.',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (!capturing && !unavailable)
            TextButton(
              onPressed: _requestSmsCaptureAuthorization,
              child: const Text('Enable'),
            ),
        ],
      ),
    );
  }

  Widget _buildHeroAggregateCard() {
    final liquid = _totalLiquidBalance;
    final spend = _totalMonthlySpend;
    final income = _totalMonthlyIncome;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22.0),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF123243), Color(0xFF0A1A25)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.auto_graph_rounded,
                    color: AppColors.primaryLight,
                    size: 16,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'TOTAL NET LIQUIDITY',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  backgroundColor: const Color(0x1A38BDF8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(
                  Icons.paste_rounded,
                  size: 13,
                  color: AppColors.infoLight,
                ),
                label: const Text(
                  'Import Text',
                  style: TextStyle(
                    color: AppColors.infoLight,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: _showImportSmsStatementDialog,
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  backgroundColor: const Color(0x1A6366F1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(
                  Icons.add,
                  size: 14,
                  color: AppColors.primaryLight,
                ),
                label: const Text(
                  'Add Account',
                  style: TextStyle(
                    color: AppColors.primaryLight,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: _showAddAccountDialog,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '₹${liquid.toStringAsFixed(2)}',
            style: TextStyle(
              color: liquid >= 0
                  ? AppColors.textPrimary
                  : AppColors.dangerLight,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.0,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Live balance across your connected accounts',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0x1AF43F5E),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.arrow_upward_rounded,
                          color: AppColors.dangerLight,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Total Outflow',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '₹${spend.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: AppColors.dangerLight,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(height: 30, width: 1, color: AppColors.border),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0x1A10B981),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.arrow_downward_rounded,
                          color: AppColors.successLight,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Total Inflow',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '₹${income.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: AppColors.successLight,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (accounts.isNotEmpty || recentTransactions.isNotEmpty) ...[
                  IconButton(
                    icon: const Icon(
                      Icons.delete_sweep_outlined,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                    tooltip: 'Clear Stored Data',
                    onPressed: _clearSampleData,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // ACCOUNTS SECTION & SMART BANKING CARDS
  // ==========================================
  Widget _buildAccountsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Text(
                  'Your Accounts',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${accounts.length}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (accounts.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Color(0x1A6366F1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_outlined,
                    color: AppColors.primaryLight,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'No accounts configured yet',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tap "+ Add Account" or "Import Text" to map your real financial data.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text(
                    'Add Your Bank Account',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: _showAddAccountDialog,
                ),
              ],
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth >= 480 ? 2 : 1;
              final itemWidth =
                  (constraints.maxWidth - (crossAxisCount - 1) * 12) /
                  crossAxisCount;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: accounts.map((acc) {
                  return SizedBox(
                    width: itemWidth,
                    child: _buildSmartAccountCard(acc),
                  );
                }).toList(),
              );
            },
          ),
      ],
    );
  }

  Widget _buildSmartAccountCard(FinancialAccount acc) {
    final isLoan = acc.type == 'LOAN';
    final isCredit = acc.type == 'CREDIT_CARD';
    final cardGradient = isLoan
        ? const LinearGradient(
            colors: [Color(0xFF3B154D), Color(0xFF200D2E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : (isCredit
              ? const LinearGradient(
                  colors: [Color(0xFF2E1A47), Color(0xFF1B112B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : const LinearGradient(
                  colors: [Color(0xFF132238), Color(0xFF0D1726)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ));

    final borderColor = isLoan
        ? const Color(0xFFC084FC)
        : (isCredit ? const Color(0x66A855F7) : const Color(0x6638BDF8));

    final badgeColor = isLoan
        ? const Color(0x33C084FC)
        : (isCredit ? const Color(0x33A855F7) : const Color(0x3338BDF8));
    final badgeTextColor = isLoan
        ? const Color(0xFFE9D5FF)
        : (isCredit ? const Color(0xFFD8B4FE) : const Color(0xFF7DD3FC));
    final badgeIcon = isLoan
        ? Icons.account_balance_wallet_rounded
        : (isCredit
              ? Icons.credit_card_rounded
              : Icons.account_balance_rounded);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: cardGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  acc.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 10, color: badgeTextColor),
                    const SizedBox(width: 4),
                    Text(
                      isLoan ? 'LOAN' : (isCredit ? 'CREDIT CARD' : 'SAVINGS'),
                      style: TextStyle(
                        color: badgeTextColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (isLoan) ...[
                const SizedBox(width: 4),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(
                    Icons.edit_note,
                    color: Color(0xFFA78BFA),
                    size: 20,
                  ),
                  tooltip: 'Edit Loan Details',
                  onPressed: () => _showEditLoanAccountDialog(acc),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (isLoan) ...[
            Row(
              children: [
                Text(
                  '₹${(acc.emiAmount ?? 0.0).toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFFC084FC),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  '/ month',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
            if (acc.currentBalance > 0 ||
                (acc.principalAmount != null && acc.principalAmount! > 0))
              Text(
                'Balance: ₹${acc.currentBalance > 0 ? acc.currentBalance.toStringAsFixed(0) : (acc.principalAmount?.toStringAsFixed(0) ?? "0")} left',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
          ] else ...[
            Text(
              '₹${acc.currentBalance.toStringAsFixed(2)}',
              style: TextStyle(
                color: isCredit
                    ? const Color(0xFFE9D5FF)
                    : (acc.currentBalance >= 0
                          ? AppColors.successLight
                          : AppColors.dangerLight),
                fontSize: 19,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              isCredit
                  ? 'Current Spend / Outstanding'
                  : (acc.anchorDate != null
                        ? 'Live Balance (Anchor: ${acc.anchorDate!.day}/${acc.anchorDate!.month})'
                        : 'Available Balance'),
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '•••• ${acc.lastFourDigits}',
                style: const TextStyle(
                  color: Colors.white38,
                  fontFamily: 'monospace',
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
              Icon(
                isCredit
                    ? Icons.credit_card
                    : (isLoan
                          ? Icons.account_balance_wallet
                          : Icons.account_balance),
                size: 14,
                color: Colors.white30,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showEditLoanAccountDialog(FinancialAccount loanAcc) async {
    final nameController = TextEditingController(text: loanAcc.name);
    final lenderController = TextEditingController(
      text: loanAcc.lenderName ?? '',
    );
    final emiController = TextEditingController(
      text: loanAcc.emiAmount != null
          ? loanAcc.emiAmount!.toStringAsFixed(2)
          : '',
    );
    final originalPrincipalController = TextEditingController(
      text: loanAcc.principalAmount != null
          ? loanAcc.principalAmount!.toStringAsFixed(2)
          : '',
    );
    final remainingPrincipalController = TextEditingController(
      text: loanAcc.currentBalance > 0
          ? loanAcc.currentBalance.toStringAsFixed(2)
          : (loanAcc.principalAmount != null
                ? loanAcc.principalAmount!.toStringAsFixed(2)
                : ''),
    );
    final rateController = TextEditingController(
      text: loanAcc.interestRatePercent != null
          ? loanAcc.interestRatePercent!.toString()
          : '',
    );
    final totalInstallmentsController = TextEditingController(
      text: loanAcc.totalInstallments != null
          ? loanAcc.totalInstallments!.toString()
          : '',
    );
    final completedController = TextEditingController(
      text: loanAcc.completedInstallments != null
          ? loanAcc.completedInstallments!.toString()
          : '1',
    );

    final updated = await showDialog<FinancialAccount>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final totalM = int.tryParse(totalInstallmentsController.text.trim());
          final paidM = int.tryParse(completedController.text.trim()) ?? 1;
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
                  child: const Icon(
                    Icons.account_balance,
                    color: Color(0xFFA78BFA),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Manage Loan Details',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'A/C •••• ${loanAcc.lastFourDigits}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
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
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Loan Account Name',
                      labelStyle: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: lenderController,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Lender / Bank',
                            labelStyle: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: emiController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Monthly EMI (₹)',
                            labelStyle: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Principal & Outstanding Balance',
                    style: TextStyle(
                      color: Color(0xFFA78BFA),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: originalPrincipalController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Original Loan (₹)',
                            hintText: 'Taken at start',
                            hintStyle: const TextStyle(
                              color: Colors.white24,
                              fontSize: 10,
                            ),
                            labelStyle: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                            helperText: 'Sanctioned amount',
                            helperStyle: const TextStyle(
                              color: Colors.white38,
                              fontSize: 9,
                            ),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: remainingPrincipalController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Remaining Balance (₹)',
                            hintText: 'Current debt left',
                            hintStyle: const TextStyle(
                              color: Colors.white24,
                              fontSize: 10,
                            ),
                            labelStyle: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                            helperText: 'Outstanding principal',
                            helperStyle: const TextStyle(
                              color: Colors.white38,
                              fontSize: 9,
                            ),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Tenure & Installments',
                    style: TextStyle(
                      color: Color(0xFFA78BFA),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: totalInstallmentsController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                          onChanged: (_) => setDialogState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Total Months',
                            hintText: 'e.g. 36',
                            hintStyle: const TextStyle(
                              color: Colors.white24,
                              fontSize: 10,
                            ),
                            labelStyle: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                            helperText: 'Total loan tenure',
                            helperStyle: const TextStyle(
                              color: Colors.white38,
                              fontSize: 9,
                            ),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: completedController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                          onChanged: (_) => setDialogState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Paid Months',
                            hintText: 'e.g. 12',
                            hintStyle: const TextStyle(
                              color: Colors.white24,
                              fontSize: 10,
                            ),
                            labelStyle: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                            helperText: 'Paid installments',
                            helperStyle: const TextStyle(
                              color: Colors.white38,
                              fontSize: 9,
                            ),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (remainingM != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x1A34D399),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0x3334D399)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_outline,
                            color: Color(0xFF34D399),
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$remainingM months remaining ($paidM of $totalM paid)',
                            style: const TextStyle(
                              color: Color(0xFFA7F3D0),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: rateController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Interest Rate % (Annual)',
                      labelStyle: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () {
                  final emiVal =
                      double.tryParse(
                        emiController.text.trim().replaceAll(',', ''),
                      ) ??
                      loanAcc.emiAmount;
                  final origPrincipalVal =
                      double.tryParse(
                        originalPrincipalController.text.trim().replaceAll(
                          ',',
                          '',
                        ),
                      ) ??
                      loanAcc.principalAmount;
                  final remPrincipalVal =
                      double.tryParse(
                        remainingPrincipalController.text.trim().replaceAll(
                          ',',
                          '',
                        ),
                      ) ??
                      loanAcc.currentBalance;
                  final rateVal =
                      double.tryParse(
                        rateController.text.trim().replaceAll(',', ''),
                      ) ??
                      loanAcc.interestRatePercent;
                  final totalMonths =
                      int.tryParse(totalInstallmentsController.text.trim()) ??
                      loanAcc.totalInstallments;
                  final paidMonths =
                      int.tryParse(completedController.text.trim()) ??
                      loanAcc.completedInstallments;

                  final updatedAcc = loanAcc.copyWith(
                    name: nameController.text.trim().isNotEmpty
                        ? nameController.text.trim()
                        : loanAcc.name,
                    lenderName: lenderController.text.trim(),
                    emiAmount: emiVal,
                    principalAmount: origPrincipalVal,
                    currentBalance: remPrincipalVal,
                    interestRatePercent: rateVal,
                    totalInstallments: totalMonths,
                    completedInstallments: paidMonths,
                  );
                  Navigator.of(ctx).pop(updatedAcc);
                },
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Update Loan'),
              ),
            ],
          );
        },
      ),
    );

    if (updated != null) {
      setState(() {
        final idx = accounts.indexWhere((a) => a.id == loanAcc.id);
        if (idx != -1) {
          accounts[idx] = updated;
        }
      });
      await _savePersistentState(
        isHistoricalBackfilled,
        lastBackfillScanTime ?? DateTime.now(),
      );
      if (AuthService().isAuthenticated) {
        BackendApiService().createAccount(updated);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Updated loan: ${updated.name}'),
            backgroundColor: const Color(0xFF8B5CF6),
          ),
        );
      }
    }
  }

  // ==========================================
  // AUTO-SYNC SCHEDULE CARD
  // ==========================================
  Widget _buildAutoSyncScheduleCard() {
    final scheduler = AutoScanSchedulerService();
    final auth = AuthService();
    final isLinked = auth.isAuthenticated && auth.hasGmailAccess;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isLinked
              ? const Color(0xFF10B981).withValues(alpha: 0.35)
              : const Color(0xFF334155),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isLinked
                  ? const Color(0xFF10B981).withValues(alpha: 0.15)
                  : const Color(0xFF334155),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.schedule_outlined,
              size: 20,
              color: isLinked ? const Color(0xFF10B981) : Colors.white54,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Flexible(
                      child: Text(
                        'Auto-Sync Schedule',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isLinked
                            ? const Color(0xFF10B981).withValues(alpha: 0.2)
                            : const Color(0xFF64748B).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isLinked ? 'ACTIVE' : 'IDLE',
                        style: TextStyle(
                          color: isLinked
                              ? const Color(0xFF10B981)
                              : const Color(0xFF94A3B8),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  isLinked
                      ? 'Hourly (6 AM – 9 PM) • Overnight catch-up (6 AM)'
                      : 'Sign in with Gmail to enable automated background sync',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                if (isLinked)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      scheduler.statusSummary,
                      style: const TextStyle(
                        color: Color(0xFF38BDF8),
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (isLinked)
            TextButton.icon(
              onPressed: (scheduler.isScanningNow || isScanning30Days)
                  ? null
                  : _runIncrementalScanSinceLastScan,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                backgroundColor: const Color(
                  0xFF10B981,
                ).withValues(alpha: 0.15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: (scheduler.isScanningNow || isScanning30Days)
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Color(0xFF10B981),
                      ),
                    )
                  : const Icon(Icons.sync, size: 14, color: Color(0xFF10B981)),
              label: const Text(
                'Scan Since Last',
                style: TextStyle(
                  color: Color(0xFF10B981),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ==========================================
  // PEER DEBT GLANCE CARD
  // ==========================================
  Widget _buildPeerDebtGlanceCard(
    BuildContext context,
    double totalOwedToMe,
    List<ContactDebtSummary> summaries,
  ) {
    return GestureDetector(
      onTap: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (context) => const PeerDebtScreen()));
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.purple.withValues(alpha: 0.35)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x148B5CF6),
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Color(0x1F8B5CF6),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.handshake_outlined,
                color: AppColors.purpleLight,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Peer Lending & Debt Ledger',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    summaries.isEmpty
                        ? 'No active debts'
                        : '${summaries.length} active contacts • ₹${totalOwedToMe.toStringAsFixed(0)} owed to you',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              color: AppColors.purpleLight,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // RECENT TRANSACTIONS SECTION & RICH ITEMS
  // ==========================================
  Widget _buildRecentTransactionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Text(
                  'Recent Transactions',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${recentTransactions.length}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (recentTransactions.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  color: AppColors.textMuted,
                  size: 36,
                ),
                SizedBox(height: 10),
                Text(
                  'No transactions recorded yet',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Transactions from your 30-day scan or "+ Add Transaction" will appear here.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          ...recentTransactions.map((txn) => _buildTransactionItemTile(txn)),
      ],
    );
  }

  String _formatTxnDateTime(DateTime dt) {
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
      'Dec',
    ];
    final dateStr = isToday
        ? 'Today'
        : '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final minuteStr = dt.minute.toString().padLeft(2, '0');
    return '$dateStr • $hour:$minuteStr $ampm';
  }

  Widget _buildTransactionItemTile(TransactionItem txn) {
    final isDebit = txn.type == 'DEBIT';
    final catColor = AppColors.getCategoryColor(txn.categoryId ?? '');
    final catIcon = AppColors.getCategoryIcon(txn.categoryId ?? '');

    return InkWell(
      onTap: () => _showTransactionDetailsModal(context, txn),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: catColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(catIcon, color: catColor, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    txn.merchantName,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${txn.categoryId ?? "Uncategorized"}${txn.subCategory != null && txn.subCategory!.isNotEmpty ? " › ${txn.subCategory}" : ""}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          txn.ingestionSource,
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time_rounded,
                        size: 11,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatTxnDateTime(txn.timestamp),
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                      if (txn.accountMask != null &&
                          txn.accountMask!.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          '• ${txn.accountMask}',
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  txn.isTransfer
                      ? '⇄ ₹${txn.amount.toStringAsFixed(2)}'
                      : '${isDebit ? '-' : '+'}₹${txn.amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: txn.isTransfer
                        ? const Color(0xFF22D3EE)
                        : (isDebit
                              ? AppColors.dangerLight
                              : AppColors.successLight),
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                if (!txn.isTransfer) ...[
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => _openSplitModal(txn),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x1A6366F1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0x406366F1)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.call_split_rounded,
                            size: 10,
                            color: Color(0xFFA5B4FC),
                          ),
                          SizedBox(width: 3),
                          Text(
                            'Split',
                            style: TextStyle(
                              color: Color(0xFFA5B4FC),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x2206B6D4),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0x5506B6D4)),
                    ),
                    child: Text(
                      _getSelfTransferRouteText(txn),
                      style: const TextStyle(
                        color: Color(0xFF22D3EE),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TRANSACTION DETAILS MODAL
  // ==========================================
  void _showTransactionDetailsModal(BuildContext context, TransactionItem txn) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDebit = txn.type == 'DEBIT';
          final catColor = AppColors.getCategoryColor(txn.categoryId ?? '');
          final catIcon = AppColors.getCategoryIcon(txn.categoryId ?? '');
          final entity = EntityService().matchEntity(
            upiId: txn.referenceNumber,
            accountMask: txn.accountMask,
            rawName: txn.merchantName,
          );

          return Dialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFF334155)),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540, maxHeight: 720),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header: Icon + Title + Close Button
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: catColor.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(catIcon, color: catColor, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                txn.merchantName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${txn.categoryId ?? "Uncategorized"}${txn.subCategory != null && txn.subCategory!.isNotEmpty ? " › ${txn.subCategory}" : ""}',
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white54,
                            size: 20,
                          ),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Amount Banner
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Transaction Amount',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                txn.isTransfer
                                    ? '⇄ ₹${txn.amount.toStringAsFixed(2)}'
                                    : '${isDebit ? '-' : '+'}₹${txn.amount.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: txn.isTransfer
                                      ? const Color(0xFF22D3EE)
                                      : (isDebit
                                            ? const Color(0xFFF87171)
                                            : const Color(0xFF34D399)),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 22,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: txn.isTransfer
                                  ? const Color(0x2206B6D4)
                                  : (isDebit
                                        ? const Color(0x22EF4444)
                                        : const Color(0x2210B981)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              txn.isTransfer
                                  ? 'SELF TRANSFER'
                                  : (isDebit
                                        ? 'DEBIT / OUTFLOW'
                                        : 'CREDIT / INFLOW'),
                              style: TextStyle(
                                color: txn.isTransfer
                                    ? const Color(0xFF22D3EE)
                                    : (isDebit
                                          ? const Color(0xFFF87171)
                                          : const Color(0xFF34D399)),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Scrollable Transaction Details
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDetailRow(
                              Icons.calendar_today_outlined,
                              'Date & Time',
                              _formatTxnDateTime(txn.timestamp),
                            ),
                            if (txn.isTransfer ||
                                txn.categoryId == 'Self Transfer') ...[
                              Builder(
                                builder: (context) {
                                  final cleanAcct = (txn.accountMask ?? '')
                                      .replaceAll('→', '')
                                      .trim();
                                  final myMask =
                                      (cleanAcct.isNotEmpty &&
                                          cleanAcct.length >= 4)
                                      ? cleanAcct
                                      : _extractMaskFromSnippet(txn.rawSnippet);
                                  final cleanCounterpart =
                                      (txn.transferCounterpartMask ?? '')
                                          .replaceAll('→', '')
                                          .trim();
                                  final counterpartMask =
                                      (cleanCounterpart.isNotEmpty &&
                                          cleanCounterpart.length >= 4)
                                      ? cleanCounterpart
                                      : _findCounterpartTransferMask(txn);

                                  final isDebit = txn.type == 'DEBIT';
                                  final fromAcct = isDebit
                                      ? myMask
                                      : counterpartMask;
                                  final toAcct = isDebit
                                      ? counterpartMask
                                      : myMask;

                                  final routeStr =
                                      (fromAcct != null &&
                                          toAcct != null &&
                                          fromAcct != toAcct)
                                      ? '$fromAcct → $toAcct'
                                      : (fromAcct != null
                                            ? '$fromAcct (Source)'
                                            : (toAcct != null
                                                  ? '$toAcct (Destination)'
                                                  : 'Internal Transfer'));

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildDetailRow(
                                        Icons.swap_horiz_rounded,
                                        'Transfer Route',
                                        routeStr,
                                      ),
                                      if (fromAcct != null &&
                                          fromAcct.isNotEmpty)
                                        _buildDetailRow(
                                          Icons.arrow_upward_rounded,
                                          'Debited From',
                                          fromAcct,
                                        ),
                                      if (toAcct != null && toAcct.isNotEmpty)
                                        _buildDetailRow(
                                          Icons.arrow_downward_rounded,
                                          'Credited To',
                                          toAcct,
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ] else ...[
                              _buildDetailRow(
                                Icons.account_balance_outlined,
                                'Account',
                                txn.accountMask ?? 'Not specified',
                              ),
                            ],
                            _buildDetailRow(
                              Icons.category_outlined,
                              'Category',
                              txn.categoryId ?? 'General Expenses',
                            ),
                            if (txn.subCategory != null &&
                                txn.subCategory!.isNotEmpty)
                              _buildDetailRow(
                                Icons.subdirectory_arrow_right,
                                'Sub-Category',
                                txn.subCategory!,
                              ),
                            _buildDetailRow(
                              Icons.source_outlined,
                              'Ingestion Source',
                              txn.ingestionSource,
                            ),
                            _buildDetailRow(
                              Icons.verified_outlined,
                              'Status',
                              txn.reconciliationStatus,
                            ),
                            if (txn.referenceNumber != null &&
                                txn.referenceNumber!.isNotEmpty)
                              _buildDetailRow(
                                Icons.tag,
                                'Reference / UPI ID',
                                txn.referenceNumber!,
                              ),

                            // Linked Shop Entity & Aliases Info
                            if (entity != null &&
                                (entity.upiAliases.isNotEmpty ||
                                    entity.vendorAliases.isNotEmpty)) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(
                                      0xFF38BDF8,
                                    ).withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.storefront,
                                          color: Color(0xFF38BDF8),
                                          size: 16,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Shop Entity: ${entity.name}',
                                          style: const TextStyle(
                                            color: Color(0xFFBAE6FD),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (entity.upiAliases.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      const Text(
                                        'Linked UPI IDs (all QR codes map to this shop):',
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 10,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      ...entity.upiAliases.map(
                                        (u) => Padding(
                                          padding: const EdgeInsets.only(
                                            left: 4,
                                            bottom: 2,
                                          ),
                                          child: Text(
                                            '• $u',
                                            style: const TextStyle(
                                              color: Color(0xFF93C5FD),
                                              fontSize: 11,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (entity.vendorAliases.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Known Vendor Names:',
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 10,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      ...entity.vendorAliases.map(
                                        (v) => Padding(
                                          padding: const EdgeInsets.only(
                                            left: 4,
                                            bottom: 2,
                                          ),
                                          child: Text(
                                            '• $v',
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],

                            // Raw Snippet Box
                            if (txn.rawSnippet != null &&
                                txn.rawSnippet!.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              const Text(
                                'Bank Alert Snippet',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Text(
                                  txn.rawSnippet!,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Actions Footer: Edit Category / Alias / Split
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF38BDF8),
                              side: const BorderSide(color: Color(0xFF38BDF8)),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: const Icon(Icons.edit, size: 14),
                            label: const Text(
                              'Edit Shop / Category',
                              style: TextStyle(fontSize: 12),
                            ),
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              _showEditTransactionDialog(context, txn);
                            },
                          ),
                        ),
                        if (!txn.isTransfer) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(
                                Icons.call_split_rounded,
                                size: 14,
                              ),
                              label: const Text(
                                'Split Expense',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _openSplitModal(txn);
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 10),
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // EDIT TRANSACTION & MAP ENTITY DIALOG
  // ==========================================
  void _showEditTransactionDialog(BuildContext context, TransactionItem txn) {
    final nameCtrl = TextEditingController(text: txn.merchantName);
    String currentCat = txn.categoryId ?? 'General Expenses';
    if (!ExpenseCategories.categories.contains(currentCat))
      currentCat = 'General Expenses';
    String? currentSub = txn.subCategory;
    final availableSubs =
        ExpenseCategories.defaultSubCategories[currentCat] ?? [];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final existingShopNames = <String>{};
          for (final e in EntityService().entities) {
            if (e.name.isNotEmpty && e.name != 'Self Transfer')
              existingShopNames.add(e.name);
          }
          for (final t in recentTransactions) {
            if (t.merchantName.isNotEmpty &&
                t.merchantName != 'Self Transfer' &&
                t.merchantName != 'Bank Alert') {
              existingShopNames.add(t.merchantName);
            }
          }
          existingShopNames.removeWhere(
            (s) => s.toLowerCase() == txn.merchantName.toLowerCase(),
          );

          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFF334155)),
            ),
            title: const Row(
              children: [
                Icon(Icons.edit_note, color: Color(0xFF38BDF8), size: 22),
                SizedBox(width: 8),
                Text(
                  'Edit Shop & Category',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Shop / Merchant Name:',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'e.g. Chicken shop, Jam roll bakery',
                      hintStyle: const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon: const Icon(
                        Icons.storefront_outlined,
                        color: Color(0xFF38BDF8),
                        size: 18,
                      ),
                    ),
                  ),
                  if (existingShopNames.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'Quick-link to existing shop / alias:',
                      style: TextStyle(
                        color: Color(0xFF93C5FD),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: existingShopNames.take(6).map((shop) {
                        return ActionChip(
                          backgroundColor: const Color(0xFF0F172A),
                          side: const BorderSide(color: Color(0xFF334155)),
                          label: Text(
                            shop,
                            style: const TextStyle(
                              color: Color(0xFFE2E8F0),
                              fontSize: 11,
                            ),
                          ),
                          onPressed: () {
                            setDialogState(() {
                              nameCtrl.text = shop;
                              final ent = EntityService().entities
                                  .where(
                                    (e) =>
                                        e.name.toLowerCase() ==
                                        shop.toLowerCase(),
                                  )
                                  .firstOrNull;
                              if (ent?.defaultCategory != null) {
                                currentCat = ent!.defaultCategory!;
                                currentSub = ent.defaultSubCategory;
                              } else {
                                final exTxn = recentTransactions
                                    .where(
                                      (t) =>
                                          t.merchantName.toLowerCase() ==
                                          shop.toLowerCase(),
                                    )
                                    .firstOrNull;
                                if (exTxn?.categoryId != null) {
                                  currentCat = exTxn!.categoryId!;
                                  currentSub = exTxn.subCategory;
                                }
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 14),
                  const Text(
                    'Category:',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
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
                        value: currentCat,
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                        isExpanded: true,
                        items: ExpenseCategories.categories
                            .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              currentCat = val;
                              final subs =
                                  ExpenseCategories.defaultSubCategories[val] ??
                                  [];
                              currentSub = subs.isNotEmpty ? subs.first : null;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Sub-Category:',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
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
                        value:
                            (availableSubs.contains(currentSub) &&
                                currentSub != null)
                            ? currentSub
                            : (availableSubs.isNotEmpty
                                  ? availableSubs.first
                                  : null),
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(
                          color: Color(0xFF93C5FD),
                          fontSize: 12,
                        ),
                        isExpanded: true,
                        items: availableSubs
                            .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => currentSub = val);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.check, size: 16, color: Colors.white),
                label: const Text(
                  'Save Changes',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: () async {
                  final newName = nameCtrl.text.trim();
                  if (newName.isNotEmpty) {
                    final oldCategory = txn.categoryId;
                    final updatedTxn = txn.copyWith(
                      merchantName: newName,
                      categoryId: currentCat,
                      subCategory: currentSub,
                    );
                    final idx = recentTransactions.indexWhere(
                      (t) => t.id == txn.id,
                    );
                    if (idx >= 0) {
                      recentTransactions[idx] = updatedTxn;
                    }

                    // Update categoryTotals
                    if (updatedTxn.type == 'DEBIT' && !updatedTxn.isTransfer) {
                      if (oldCategory != null &&
                          categoryTotals.containsKey(oldCategory)) {
                        categoryTotals[oldCategory] =
                            (categoryTotals[oldCategory]! - updatedTxn.amount)
                                .clamp(0.0, double.infinity);
                      }
                      categoryTotals[currentCat] =
                          (categoryTotals[currentCat] ?? 0.0) +
                          updatedTxn.amount;
                    }

                    // Map entity and aliases so future transactions recognize this shop
                    await EntityService().mapTransactionToEntity(
                      entityName: newName,
                      rawVendorName: txn.merchantName != newName
                          ? txn.merchantName
                          : null,
                      upiId: txn.referenceNumber,
                      accountMask: txn.accountMask,
                      category: currentCat,
                      subCategory: currentSub,
                    );

                    await _savePersistentState(
                      isHistoricalBackfilled,
                      lastBackfillScanTime ?? DateTime.now(),
                    );
                    if (AuthService().isAuthenticated) {
                      BackendApiService().createTransaction(updatedTxn);
                    }
                    if (mounted) setState(() {});
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  // ==========================================
  // MODAL FOR MANUAL TRANSACTION ENTRY
  // ==========================================
  void _showAddTransactionDialog() {
    final merchantCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String selectedCategory = 'Food & Dining';
    String selectedAccount = accounts.isNotEmpty
        ? accounts.first.id
        : 'acc-default';
    bool isDebit = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Record Transaction',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Debit (Expense)'),
                        selected: isDebit,
                        selectedColor: const Color(0x33F43F5E),
                        onSelected: (val) =>
                            setDialogState(() => isDebit = true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Credit (Income)'),
                        selected: !isDebit,
                        selectedColor: const Color(0x3310B981),
                        onSelected: (val) =>
                            setDialogState(() => isDebit = false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: merchantCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText:
                        'Merchant / Payee Name (e.g. Swiggy, Amazon, Salary)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Amount (INR)',
                    prefixText: '₹ ',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  dropdownColor: AppColors.surfaceElevated,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: const [
                    DropdownMenuItem(
                      value: 'Food & Dining',
                      child: Text('Food & Dining'),
                    ),
                    DropdownMenuItem(
                      value: 'Shopping',
                      child: Text('Shopping'),
                    ),
                    DropdownMenuItem(
                      value: 'Transport & Fuel',
                      child: Text('Transport & Fuel'),
                    ),
                    DropdownMenuItem(
                      value: 'Bills & Utilities',
                      child: Text('Bills & Utilities'),
                    ),
                    DropdownMenuItem(
                      value: 'Groceries',
                      child: Text('Groceries'),
                    ),
                    DropdownMenuItem(
                      value: 'Salary & Income',
                      child: Text('Salary & Income'),
                    ),
                    DropdownMenuItem(
                      value: 'General Expenses',
                      child: Text('General Expenses'),
                    ),
                  ],
                  onChanged: (v) => setDialogState(
                    () => selectedCategory = v ?? selectedCategory,
                  ),
                ),
                const SizedBox(height: 12),
                if (accounts.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: accounts.any((a) => a.id == selectedAccount)
                        ? selectedAccount
                        : accounts.first.id,
                    dropdownColor: AppColors.surfaceElevated,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'Account'),
                    items: accounts
                        .map(
                          (a) => DropdownMenuItem(
                            value: a.id,
                            child: Text('${a.name} (••• ${a.lastFourDigits})'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setDialogState(
                      () => selectedAccount = v ?? selectedAccount,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              onPressed: () {
                final amt = double.tryParse(amountCtrl.text.trim());
                final merchant = merchantCtrl.text.trim();
                if (amt == null || amt <= 0 || merchant.isEmpty) return;

                final newTxn = TransactionItem(
                  id: 'txn-manual-${DateTime.now().millisecondsSinceEpoch}',
                  amount: amt,
                  currency: 'INR',
                  type: isDebit ? 'DEBIT' : 'CREDIT',
                  merchantName: merchant,
                  accountId: selectedAccount,
                  categoryId: selectedCategory,
                  ingestionSource: 'MANUAL',
                  reconciliationStatus: 'CONFIRMED',
                  timestamp: DateTime.now(),
                );

                setState(() {
                  _addConfirmedTransaction(newTxn);

                  if (isDebit) {
                    categoryTotals[selectedCategory] =
                        (categoryTotals[selectedCategory] ?? 0.0) + amt;
                  }

                  final idx = accounts.indexWhere(
                    (a) => a.id == selectedAccount,
                  );
                  if (idx != -1) {
                    final acc = accounts[idx];
                    final updatedBal = isDebit
                        ? (acc.currentBalance - amt)
                        : (acc.currentBalance + amt);
                    accounts[idx] = FinancialAccount(
                      id: acc.id,
                      name: acc.name,
                      type: acc.type,
                      lastFourDigits: acc.lastFourDigits,
                      currency: acc.currency,
                      currentBalance: updatedBal,
                    );
                  }
                  recentTransactions.sort(
                    (a, b) => b.timestamp.compareTo(a.timestamp),
                  );
                });

                _savePersistentState(
                  isHistoricalBackfilled,
                  lastBackfillScanTime ?? DateTime.now(),
                );
                BackendApiService().createTransaction(newTxn);
                Navigator.of(ctx).pop();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Recorded ₹${amt.toStringAsFixed(2)} at $merchant successfully!',
                    ),
                    backgroundColor: AppColors.success,
                  ),
                );
              },
              child: const Text(
                'Save Transaction',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // MODAL FOR ADDING AN ACCOUNT
  // ==========================================
  void _showAddAccountDialog() {
    final nameCtrl = TextEditingController();
    final last4Ctrl = TextEditingController();
    final balanceCtrl = TextEditingController();
    String accountType = 'SAVINGS';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Add Bank Account / Card',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText:
                        'Account / Bank Name (e.g. HDFC Salary, ICICI Card)',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: last4Ctrl,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Last 4 Digits',
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: accountType,
                        dropdownColor: AppColors.surfaceElevated,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(labelText: 'Type'),
                        items: const [
                          DropdownMenuItem(
                            value: 'SAVINGS',
                            child: Text('Savings'),
                          ),
                          DropdownMenuItem(
                            value: 'CURRENT',
                            child: Text('Current'),
                          ),
                          DropdownMenuItem(
                            value: 'CREDIT_CARD',
                            child: Text('Credit Card'),
                          ),
                        ],
                        onChanged: (v) => setDialogState(
                          () => accountType = v ?? accountType,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: balanceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Current Balance (INR)',
                    prefixText: '₹ ',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
              ),
              onPressed: () {
                final name = nameCtrl.text.trim();
                final last4 = last4Ctrl.text.trim().isEmpty
                    ? '0000'
                    : last4Ctrl.text.trim();
                final bal = double.tryParse(balanceCtrl.text.trim()) ?? 0.0;
                if (name.isEmpty) return;

                final newAcc = FinancialAccount(
                  id: 'acc-${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  type: accountType,
                  lastFourDigits: last4,
                  currency: 'INR',
                  currentBalance: bal,
                );

                setState(() {
                  accounts.add(newAcc);
                });

                _savePersistentState(
                  isHistoricalBackfilled,
                  lastBackfillScanTime ?? DateTime.now(),
                );
                BackendApiService().createAccount(newAcc);
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Added account "$name (**$last4)" successfully!',
                    ),
                    backgroundColor: AppColors.success,
                  ),
                );
              },
              child: const Text(
                'Save Account',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // IMPORT SMS / STATEMENT TEXT MODAL
  // ==========================================
  void _showImportSmsStatementDialog() {
    final textCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.receipt_long, color: AppColors.infoLight, size: 22),
            SizedBox(width: 8),
            Text(
              'Import SMS or Statement Text',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Paste one or more bank SMS alerts or statement lines below. Amounts, merchants, and accounts are automatically extracted:',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textCtrl,
                maxLines: 6,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  hintText:
                      'e.g. "Sent Rs. 450.00 from HDFC Bank A/C *1234 to SWIGGY on 25-Aug-26"\n"Rs 1,200.00 spent on ICICI Card ending 9988 at AMAZON"',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.info),
            onPressed: () {
              final rawText = textCtrl.text.trim();
              if (rawText.isEmpty) return;

              final lines = rawText.split('\n');
              int parsedCount = 0;

              for (final line in lines) {
                if (line.trim().isEmpty) continue;

                // Check if it's a balance notification first!
                final snap = _extractBalanceSnapshotFromSnippet(
                  line,
                  DateTime.now().toIso8601String(),
                );
                if (snap != null) {
                  final digits = (snap['mask'] as String).replaceAll(
                    RegExp(r'[^0-9]'),
                    '',
                  );
                  final last4 = digits.length >= 4
                      ? digits.substring(digits.length - 4)
                      : digits;
                  _ensureMaskRegistered('•••• $last4');
                  final idx = accounts.indexWhere(
                    (a) => a.lastFourDigits == last4,
                  );
                  if (idx >= 0) {
                    accounts[idx] = accounts[idx].copyWith(
                      anchorBalance: snap['balance'] as double,
                      anchorDate: snap['asOfDate'] as DateTime,
                      currentBalance: snap['balance'] as double,
                    );
                  }
                  parsedCount++;
                  continue;
                }

                final parsed = SmsReceiverService.parseSmsBody(
                  line,
                  'Bank Alert',
                  DateTime.now(),
                );
                if (parsed != null) {
                  final String last4 = parsed['lastFour'];
                  final double amt = parsed['amount'];
                  final String type = parsed['type'];
                  final String merchant = parsed['merchant'];
                  final String cat = parsed['category'] ?? 'General Expenses';

                  final isCard =
                      last4 == '9207' ||
                      last4 == '9635' ||
                      line.toLowerCase().contains('credit card') ||
                      line.toLowerCase().contains('card ending');
                  _ensureMaskRegistered(
                    '•••• $last4',
                    null,
                    isCard ? 'CREDIT_CARD' : 'SAVINGS',
                  );

                  final String accId = 'acc-real-$last4';
                  _addConfirmedTransaction(
                    TransactionItem(
                      id: 'txn-import-${DateTime.now().millisecondsSinceEpoch}-$parsedCount',
                      amount: amt,
                      currency: 'INR',
                      type: type,
                      merchantName: merchant,
                      accountId: accId,
                      categoryId: cat,
                      accountMask: '•••• $last4',
                      rawSnippet: line,
                      ingestionSource: 'SMS',
                      reconciliationStatus: 'CONFIRMED',
                      timestamp: DateTime.now(),
                    ),
                  );

                  parsedCount++;
                }
              }

              _reconcileSelfTransfers();
              _computeAccountBalances();

              recentTransactions.sort(
                (a, b) => b.timestamp.compareTo(a.timestamp),
              );
              categoryTotals.clear();
              for (final t in recentTransactions) {
                if (t.type == 'DEBIT' &&
                    !t.isTransfer &&
                    t.categoryId != 'Self Transfer') {
                  final cat = t.categoryId ?? 'General Expenses';
                  categoryTotals[cat] = (categoryTotals[cat] ?? 0.0) + t.amount;
                }
              }

              setState(() {});
              _savePersistentState(
                isHistoricalBackfilled,
                lastBackfillScanTime ?? DateTime.now(),
              );
              Navigator.of(ctx).pop();

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    parsedCount > 0
                        ? 'Successfully imported $parsedCount real transactions from your text!'
                        : 'No valid financial amounts detected in pasted text.',
                  ),
                  backgroundColor: parsedCount > 0
                      ? AppColors.success
                      : AppColors.danger,
                ),
              );
            },
            child: const Text(
              'Parse & Ingest',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // RESET / CLEAR ALL DATA
  // ==========================================
  void _clearSampleData() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Clear All Stored Data?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This will clear all accounts, transactions, and categories so you have a completely clean dashboard.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              final navigator = Navigator.of(ctx);
              final messenger = ScaffoldMessenger.of(context);
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              await prefs.setInt('app_data_version', 5);
              BackendApiService().clearAllCloudData();

              if (mounted) {
                setState(() {
                  accounts.clear();
                  recentTransactions.clear();
                  pendingTransactions.clear();
                  categoryTotals.clear();
                  isHistoricalBackfilled = false;
                  lastBackfillScanTime = null;
                });
              }

              navigator.pop();
              messenger.showSnackBar(
                const SnackBar(
                  content: Text(
                    'All data cleared! Ready for your real accounts and SMS.',
                  ),
                  backgroundColor: AppColors.info,
                ),
              );
            },
            child: const Text(
              'Clear Everything',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

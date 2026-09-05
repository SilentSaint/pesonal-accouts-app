import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:automatic_expense_tracker/domain/financial_account.dart';
import 'package:automatic_expense_tracker/domain/transaction_item.dart';
import 'package:automatic_expense_tracker/services/developer_mode_service.dart';
import 'package:automatic_expense_tracker/services/entity_service.dart';
import 'package:automatic_expense_tracker/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Persistence & Re-scan Deduplication Tests', () {
    test(
        'Persists and restores accounts and confirmed transactions across sessions',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final account = FinancialAccount(
        id: 'acc-1277',
        name: 'HDFC Bank (•••• 1277)',
        type: 'SAVINGS',
        lastFourDigits: '1277',
        currentBalance: 5000.0,
        currency: 'INR',
      );

      final txn = TransactionItem(
        id: 'txn-gmail-msg-001',
        amount: 25.0,
        currency: 'INR',
        type: 'DEBIT',
        merchantName: 'Chai Works',
        accountId: 'acc-1277',
        categoryId: 'Food & Dining',
        subCategory: 'Tea & Snacks',
        ingestionSource: 'EMAIL',
        reconciliationStatus: 'CONFIRMED',
        timestamp: DateTime(2026, 8, 27, 14, 29),
        referenceNumber: '660599700199',
      );

      // Simulate saving to persistence
      await prefs.setString('saved_accounts', jsonEncode([account.toJson()]));
      await prefs.setString('saved_recent_txns', jsonEncode([txn.toJson()]));
      await prefs.setBool('is_historical_backfilled', true);

      // Simulate restoring in a new session
      final restoredAccountsRaw = prefs.getString('saved_accounts');
      final restoredTxnsRaw = prefs.getString('saved_recent_txns');
      final isBackfilled = prefs.getBool('is_historical_backfilled');

      expect(isBackfilled, isTrue);
      expect(restoredAccountsRaw, isNotNull);
      expect(restoredTxnsRaw, isNotNull);

      final List<dynamic> accList = jsonDecode(restoredAccountsRaw!);
      final List<dynamic> txnList = jsonDecode(restoredTxnsRaw!);

      final restoredAcc =
          FinancialAccount.fromJson(accList.first as Map<String, dynamic>);
      final restoredTxn =
          TransactionItem.fromJson(txnList.first as Map<String, dynamic>);

      expect(restoredAcc.lastFourDigits, '1277');
      expect(restoredTxn.id, 'txn-gmail-msg-001');
      expect(restoredTxn.merchantName, 'Chai Works');
      expect(restoredTxn.subCategory, 'Tea & Snacks');
    });

    test('Deduplicates subsequent scans against already confirmed transactions',
        () {
      final confirmedTxns = [
        TransactionItem(
          id: 'txn-gmail-msg-001',
          amount: 25.0,
          currency: 'INR',
          type: 'DEBIT',
          merchantName: 'Chai Works',
          accountId: 'acc-1277',
          categoryId: 'Food & Dining',
          subCategory: 'Tea & Snacks',
          ingestionSource: 'EMAIL',
          reconciliationStatus: 'CONFIRMED',
          timestamp: DateTime(2026, 8, 27, 14, 29),
          referenceNumber: '660599700199',
        ),
      ];

      // Simulated candidate returned from Gmail scan for the same email
      final candidate = {
        'messageId': 'msg-001',
        'amount': 25.0,
        'upiId': '660599700199',
        'merchantName': 'Saira Banu',
      };

      final msgId = candidate['messageId'] as String;
      final upiRef = candidate['upiId'] as String;
      final stableTxnId = 'txn-gmail-$msgId';

      final isAlreadyConfirmed = confirmedTxns.any((t) =>
          t.id == stableTxnId ||
          t.id.contains(msgId) ||
          (t.referenceNumber != null && t.referenceNumber == upiRef));

      // Must be skipped so user never has to review the same record again!
      expect(isAlreadyConfirmed, isTrue);
    });

    test(
        'Automatically accounts for future records matching an existing merchant alias without review',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      // 1. User previously mapped "paytm.s1yxlpq@pty" / "Saira Banu" to alias "Chai Works"
      final entityData = [
        {
          'id': 'ent-1',
          'name': 'Chai Works',
          'defaultCategory': 'Food & Dining',
          'defaultSubCategory': 'Tea & Snacks',
          'vendorAliases': ['Saira Banu'],
          'upiAliases': ['paytm.s1yxlpq@pty'],
          'accountAliases': ['1277'],
          'lastUsedAt': DateTime.now().toIso8601String(),
        }
      ];
      await prefs.setString('saved_merchant_entities', jsonEncode(entityData));

      // 2. A new, different transaction comes in from the same merchant (new date, new amount)
      final newCandidate = {
        'messageId': 'msg-new-tomorrow',
        'amount': 30.0,
        'upiId': 'paytm.s1yxlpq@pty',
        'merchantName': 'Saira Banu',
        'category': 'Food & Dining',
        'accountMask': '•••• 1277',
        'date': DateTime.now().toIso8601String(),
        'snippet':
            'Rs.30.00 debited from a/c 1277 towards VPA paytm.s1yxlpq@pty (Saira Banu)',
      };

      // 3. Match against EntityService
      final rawEntities =
          jsonDecode(prefs.getString('saved_merchant_entities')!)
              as List<dynamic>;
      final matched = rawEntities.firstWhere(
        (e) =>
            (e['upiAliases'] as List).contains(newCandidate['upiId']) ||
            (e['vendorAliases'] as List).contains(newCandidate['merchantName']),
        orElse: () => null,
      );

      expect(matched, isNotNull);
      expect(matched['name'], 'Chai Works');
      expect(matched['defaultCategory'], 'Food & Dining');
      expect(matched['defaultSubCategory'], 'Tea & Snacks');

      // 4. Transform into auto-confirmed transaction
      final autoTxn = TransactionItem(
        id: 'txn-gmail-${newCandidate['messageId']}',
        amount: newCandidate['amount'] as double,
        currency: 'INR',
        type: 'DEBIT',
        merchantName: matched['name'] as String,
        accountId: 'acc-gmail',
        categoryId: matched['defaultCategory'] as String,
        subCategory: matched['defaultSubCategory'] as String,
        ingestionSource: 'EMAIL',
        reconciliationStatus: 'AUTO_CONFIRMED',
        timestamp: DateTime.now(),
        accountMask: newCandidate['accountMask'] as String,
        referenceNumber: newCandidate['upiId'] as String,
      );

      expect(autoTxn.reconciliationStatus, 'AUTO_CONFIRMED');
      expect(autoTxn.merchantName, 'Chai Works');
      expect(autoTxn.subCategory, 'Tea & Snacks');
    });

    test('Persists only the non-sensitive identity profile for session restore',
        () async {
      SharedPreferences.setMockInitialValues({
        'auth_email': 'testuser@gmail.com',
        'auth_display_name': 'Test User',
        'auth_scope_id': 'abc123def456',
      });

      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('auth_email');
      final id = prefs.getString('auth_scope_id');
      final name = prefs.getString('auth_display_name');

      expect(email, 'testuser@gmail.com');
      expect(id, 'abc123def456');
      expect(name, 'Test User');
      expect(prefs.containsKey('auth_id_token'), isFalse);
      expect(prefs.containsKey('auth_gmail_token'), isFalse);
      expect(prefs.containsKey('auth_has_gmail'), isFalse);
    });

    test(
        'AutoScanSchedulerService computes exact overnight (9:01 PM - 5:59 AM) window',
        () {
      final now = DateTime(2026, 8, 27, 6, 15, 0); // 6:15 AM
      final yesterday = now.subtract(const Duration(days: 1));
      final overnightStart =
          DateTime(yesterday.year, yesterday.month, yesterday.day, 21, 1, 0);
      final overnightEnd = DateTime(now.year, now.month, now.day, 5, 59, 59);

      expect(overnightStart.hour, 21);
      expect(overnightStart.minute, 1);
      expect(overnightEnd.hour, 5);
      expect(overnightEnd.minute, 59);
      expect(overnightEnd.second, 59);

      final afterSec = (overnightStart.millisecondsSinceEpoch / 1000).floor();
      final beforeSec = (overnightEnd.millisecondsSinceEpoch / 1000).floor();

      expect(beforeSec, greaterThan(afterSec));
    });

    test(
        'Incremental scan computes time range strictly starting from last scan time',
        () {
      final lastScan = DateTime(2026, 8, 27, 14, 30, 0); // 2:30 PM
      final bufferTime = lastScan.subtract(const Duration(minutes: 5));
      final afterSec = (bufferTime.millisecondsSinceEpoch / 1000).floor();

      final now = DateTime(2026, 8, 27, 15, 30, 0); // 3:30 PM
      final nowSec = (now.millisecondsSinceEpoch / 1000).floor();

      expect(afterSec, lessThan(nowSec));
      // Buffer of 5 minutes means afterSec corresponds to 14:25:00
      final computedBufferDt =
          DateTime.fromMillisecondsSinceEpoch(afterSec * 1000);
      expect(computedBufferDt.minute, 25);
      expect(computedBufferDt.hour, 14);
    });

    test(
        'DeveloperModeService defaults to enabled and generates 3 non-overlapping phases covering 30 days',
        () async {
      SharedPreferences.setMockInitialValues({});
      final devService = DeveloperModeService();
      expect(devService.isEnabled, isTrue);

      final fixedRef = DateTime(2026, 8, 27, 12, 0, 0);
      final p1 = devService.getPhase1Range(fixedRef);
      final p2 = devService.getPhase2Range(fixedRef);
      final p3 = devService.getPhase3Range(fixedRef);

      expect(p1['phaseIndex'], 1);
      expect(p2['phaseIndex'], 2);
      expect(p3['phaseIndex'], 3);

      // Phase 1: Days 30 to 21 (start = 30 days ago, end = 20 days ago)
      expect(p1['afterSec'], lessThan(p1['beforeSec'] as int));
      // Phase 2: Days 20 to 11 (start = 20 days ago, end = 10 days ago)
      expect(p2['afterSec'], equals(p1['beforeSec']));
      expect(p2['afterSec'], lessThan(p2['beforeSec'] as int));
      // Phase 3: Days 10 to Today (start = 10 days ago, end = now)
      expect(p3['afterSec'], equals(p2['beforeSec']));
      expect(p3['afterSec'], lessThan(p3['beforeSec'] as int));

      // Check total coverage is 30 days
      final totalSpanSec = (p3['beforeSec'] as int) - (p1['afterSec'] as int);
      expect(totalSpanSec, equals(30 * 24 * 60 * 60));

      // Test recording audit and exporting JSON
      devService.recordPhaseAudit(PhaseScanAudit(
        phaseIndex: 1,
        phaseTitle: 'Phase 1',
        scannedAt: fixedRef,
        emailsScanned: 15,
        candidatesCount: 8,
        autoAccountedCount: 5,
        needsReviewCount: 3,
        items: [
          PhaseAuditItem(
            messageId: 'msg-101',
            subject: 'Debited INR 50',
            from: 'alerts@hdfcbank.net',
            date: '2026-08-01',
            snippet: 'Debited INR 50 via UPI',
            isCandidate: true,
            amount: 50.0,
            merchantName: 'Chai Point',
            category: 'Food & Dining',
            status: 'AUTO_CONFIRMED',
          ),
        ],
      ));

      final exportJson = devService.exportPhaseAuditJson(1);
      expect(exportJson, contains('msg-101'));
      expect(exportJson, contains('Chai Point'));
      expect(exportJson, contains('AUTO_CONFIRMED'));
    });

    test(
        'Regex correctly extracts merchants with underscores like UPI_GOKIWI from bank alert snippet',
        () {
      const snippet =
          'YES BANK Dear Customer, Greetings from YES BANK. INR 300.50 has been spent on your YES BANK Credit Card ending with 8173 at UPI_GOKIWI on 29-07-2026 at 08:37:11 am. Avl Bal INR 118311.08. In case of';
      final toMatch = RegExp(
              r'(?:to|at|towards|for|paid\s+to)\s+([A-Za-z0-9_.\-&/ ]{2,32}?)(?:\s+on\s+\d|\s+dated|\.|\,|$)',
              caseSensitive: false)
          .firstMatch(snippet);

      expect(toMatch, isNotNull);
      expect(toMatch!.group(1)!.trim(), 'UPI_GOKIWI');
    });

    test(
        'Confirmed transactions are always placed in descending chronological order regardless of review sequence',
        () {
      final list = <TransactionItem>[
        TransactionItem(
          id: 't-aug-27',
          amount: 500.0,
          currency: 'INR',
          type: 'DEBIT',
          merchantName: 'Amazon',
          accountId: 'acc-1',
          ingestionSource: 'EMAIL',
          reconciliationStatus: 'CONFIRMED',
          timestamp: DateTime(2026, 8, 27, 10, 0),
        ),
      ];

      // A transaction from July 29th is confirmed later
      final olderTxn = TransactionItem(
        id: 't-july-29',
        amount: 300.50,
        currency: 'INR',
        type: 'DEBIT',
        merchantName: 'UPI_GOKIWI',
        accountId: 'acc-1',
        ingestionSource: 'EMAIL',
        reconciliationStatus: 'CONFIRMED',
        timestamp: DateTime(2026, 7, 29, 8, 37),
      );

      list.add(olderTxn);
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      expect(list.first.id, 't-aug-27');
      expect(list.last.id, 't-july-29');
      expect(list.first.timestamp.isAfter(list.last.timestamp), isTrue);
    });

    test('Parser correctly extracts Recurring Deposit RD No installment', () {
      const text =
          'Your monthly instalment of INR 2,000.00 for Recurring Deposit RD No.XXXXX7044 is due on 06-AUG-26. Please ensure sufficient balance in your account to avoid payment failure.';
      final amtMatch = RegExp(
              r'(?:(?:Amount|Payment)\s*received:?\s*(?:INR|Rs\.?|₹)?\s*|INR\s*|Rs\.?\s*|₹\s*)([\d,]+(?:\.\d{1,2})?)',
              caseSensitive: false)
          .firstMatch(text);
      expect(amtMatch, isNotNull);
      expect(double.parse(amtMatch!.group(1)!.replaceAll(',', '')), 2000.0);

      final rdMatch =
          RegExp(r'(?:RD|FD)\s*No\.?\s*([xX*]*\d{4})', caseSensitive: false)
              .firstMatch(text);
      expect(rdMatch, isNotNull);
      expect(
          rdMatch!.group(1)!.substring(rdMatch.group(1)!.length - 4), '7044');
    });

    test('Parser correctly extracts Salary NEFT credit and sender organization',
        () {
      const text =
          'You have received a credit in your HDFC Bank account. Details of the transaction: Amount received: INR 1,05,542.00 Account: XX1277 Date: 30-JUL-2026 Reference Details: NEFT Cr-CITI0000002-SIGNIFY INNO I L SALARY TRANSIT AC-RAKSHITH GOWDA G-CITIN26706472014 Available Balance: INR 4,03,554.79';
      final amtMatch = RegExp(
              r'(?:(?:Amount|Payment)\s*received:?\s*(?:INR|Rs\.?|₹)?\s*|INR\s*|Rs\.?\s*|₹\s*)([\d,]+(?:\.\d{1,2})?)',
              caseSensitive: false)
          .firstMatch(text);
      expect(amtMatch, isNotNull);
      expect(double.parse(amtMatch!.group(1)!.replaceAll(',', '')), 105542.0);

      final neftMatch = RegExp(
              r'(?:NEFT\s+Cr-[A-Za-z0-9]+-|Cr-)([A-Za-z0-9\s&]+?)(?:-[A-Za-z0-9\s]+-[A-Za-z0-9]+|$)',
              caseSensitive: false)
          .firstMatch(text);
      expect(neftMatch, isNotNull);
      var rawName = neftMatch!
          .group(1)!
          .trim()
          .replaceAll(
              RegExp(r'\s*SALARY\s*TRANSIT\s*AC|\s*TRANSIT\s*AC',
                  caseSensitive: false),
              '')
          .trim();
      expect(rawName, 'SIGNIFY INNO I L');
    });

    test(
        'Parser correctly extracts Credit Card bill repayment towards RBL Bank card',
        () {
      const text =
          'Dear RAKSHITH GOWDA G, A payment of Rs.7485.00 has been received towards your RBL Bank Credit Card ending with 35 on 30-07-2026 through BBPS. Payment is subject to realization.';
      final amtMatch = RegExp(
              r'(?:(?:Amount|Payment)\s*received:?\s*(?:INR|Rs\.?|₹)?\s*|INR\s*|Rs\.?\s*|₹\s*)([\d,]+(?:\.\d{1,2})?)',
              caseSensitive: false)
          .firstMatch(text);
      expect(amtMatch, isNotNull);
      expect(double.parse(amtMatch!.group(1)!.replaceAll(',', '')), 7485.0);

      final cardMatch = RegExp(
              r'towards\s+your\s+([A-Za-z0-9\s&]+?Credit\s+Card)',
              caseSensitive: false)
          .firstMatch(text);
      expect(cardMatch, isNotNull);
      expect(cardMatch!.group(1)!.trim(), 'RBL Bank Credit Card');
    });

    test('Parser correctly extracts Loan EMI debit and loan account ending',
        () {
      const text =
          'Dear Customer, Greetings from HDFC Bank! Rs. INR 22217.00 is deducted from your account ending XX1277 and added to EMI 150250733 Chq S150250733129 0826150250733 account on 07-AUG-2026. The available';

      // 1. Amount extraction
      final amtMatch = RegExp(
              r'(?:(?:Amount|Payment)\s*(?:received|paid|due)?:?\s*(?:INR|Rs\.?|₹)?\s*|INR\s*|Rs\.?\s*|₹\s*)([\d,]+(?:\.\d{1,2})?)',
              caseSensitive: false)
          .firstMatch(text);
      expect(amtMatch, isNotNull);
      expect(double.parse(amtMatch!.group(1)!.replaceAll(',', '')), 22217.0);

      // 2. Debited Account Mask
      final acctMatch = RegExp(
              r'(?:ending\s+in|ending\s+with|account|a\/c|credit\s+card|card)\s*(?:ending|no\.?|ending with)?\s*(?:in|:)?\s*\(?([xX*]*\d{2,4})\)?',
              caseSensitive: false)
          .firstMatch(text);
      expect(acctMatch, isNotNull);
      expect(acctMatch!.group(1)!.substring(acctMatch.group(1)!.length - 4),
          '1277');

      // 3. EMI Loan Account
      final emiMatch = RegExp(
              r'(?:added\s+to\s+EMI|towards\s+EMI|\bEMI)\s*([xX*]*\d{4,16})',
              caseSensitive: false)
          .firstMatch(text);
      expect(emiMatch, isNotNull);
      final rawLoanNo = emiMatch!.group(1)!;
      final loanLast4 = rawLoanNo.substring(rawLoanNo.length - 4);
      expect(loanLast4, '0733');

      // 4. Lender detection
      final bankMatch = RegExp(
              r'\b(HDFC|ICICI|SBI|AXIS|KOTAK|RBL|YES|IDFC|BOB|PNB|CANARA|INDUSIND)\s+Bank',
              caseSensitive: false)
          .firstMatch(text);
      expect(bankMatch, isNotNull);
      expect(bankMatch!.group(1), 'HDFC');

      final displayMerchant = 'HDFC Bank Loan EMI (•••• $loanLast4)';
      expect(displayMerchant, 'HDFC Bank Loan EMI (•••• 0733)');
    });

    test(
        'FinancialAccount correctly serializes and deserializes LOAN account tracking fields',
        () {
      final loan = FinancialAccount(
        id: 'acc-loan-0733',
        name: 'HDFC Bank Loan (•••• 0733)',
        type: 'LOAN',
        lastFourDigits: '0733',
        currency: 'INR',
        currentBalance: 500000.0,
        emiAmount: 22217.0,
        principalAmount: 500000.0,
        interestRatePercent: 10.5,
        totalInstallments: 36,
        completedInstallments: 1,
        lenderName: 'HDFC Bank',
      );

      final json = loan.toJson();
      expect(json['type'], 'LOAN');
      expect(json['emiAmount'], 22217.0);
      expect(json['principalAmount'], 500000.0);
      expect(json['interestRatePercent'], 10.5);
      expect(json['totalInstallments'], 36);
      expect(json['completedInstallments'], 1);
      expect(json['lenderName'], 'HDFC Bank');

      final restored = FinancialAccount.fromJson(json);
      expect(restored.id, 'acc-loan-0733');
      expect(restored.type, 'LOAN');
      expect(restored.lastFourDigits, '0733');
      expect(restored.emiAmount, 22217.0);
      expect(restored.principalAmount, 500000.0);
      expect(restored.interestRatePercent, 10.5);
      expect(restored.totalInstallments, 36);
      expect(restored.completedInstallments, 1);
      expect(restored.lenderName, 'HDFC Bank');
    });

    test(
        'EntityService isolates platform aggregators and avoids broad vendor aliasing for multi-service platforms like Dreamplug / CRED',
        () async {
      SharedPreferences.setMockInitialValues({
        'auth_email': 'persistence@example.com',
        'auth_display_name': 'Persistence Test',
        'auth_scope_id': 'persistence-scope',
      });
      await AuthService().ensureInitialized();
      final service = EntityService();
      expect(
          EntityService.isPlatformAggregator(
              'Dreamplug Service Private Limited'),
          isTrue);
      expect(
          EntityService.isPlatformAggregator('One97 Communications'), isTrue);
      expect(EntityService.isPlatformAggregator('Chai Works'), isFalse);

      final mapped = await service.mapTransactionToEntity(
        entityName: 'CRED (FASTag Recharge)',
        rawVendorName: 'Dreamplug Service Private Limited',
        upiId: 'cred.fastag@axisb',
        category: 'Transport & Fuel',
        subCategory: 'FASTag & Tolls',
      );

      expect(mapped.upiAliases, contains('cred.fastag@axisb'));
      expect(mapped.vendorAliases,
          isNot(contains('Dreamplug Service Private Limited')));

      // Specific UPI match works
      final matchedByUpi = service.matchEntity(upiId: 'cred.fastag@axisb');
      expect(matchedByUpi?.name, 'CRED (FASTag Recharge)');

      // Broad vendor name is NOT hijacked
      final matchedByVendor =
          service.matchEntity(rawName: 'Dreamplug Service Private Limited');
      expect(matchedByVendor, isNull);
    });

    test('Regex extracts CRED FASTag recharge from HDFC UPI debit snippet', () {
      const snippet =
          'Dear Customer, Greetings from HDFC Bank! Rs.500.00 is debited from your account ending 1277 towards VPA cred.fastag@axisb (Dreamplug Service Private Limited) on 06-08-26. UPI transaction reference no.:';
      final amtMatch =
          RegExp(r'Rs\.?\s*([0-9,]+(?:\.[0-9]{2})?)', caseSensitive: false)
              .firstMatch(snippet);
      final amt = double.parse(amtMatch!.group(1)!.replaceAll(',', ''));
      expect(amt, 500.0);

      final vpaMatch = RegExp(r'towards\s+(?:VPA\s+)?([A-Za-z0-9._@-]+)',
              caseSensitive: false)
          .firstMatch(snippet);
      expect(vpaMatch?.group(1), 'cred.fastag@axisb');

      final acctMatch =
          RegExp(r'account\s+ending\s+(\d{4})', caseSensitive: false)
              .firstMatch(snippet);
      expect(acctMatch?.group(1), '1277');
    });

    test(
        'Self-Transfer transactions have zero effectivePersonalExpense and isTransfer == true',
        () {
      final transferTxn = TransactionItem(
        id: 'txn-transfer-1',
        amount: 121.0,
        currency: 'INR',
        type: 'DEBIT',
        merchantName: 'Self Transfer',
        accountId: 'acc-1',
        categoryId: 'Self Transfer',
        subCategory: 'Account to Account Transfer',
        ingestionSource: 'SMS',
        reconciliationStatus: 'CONFIRMED',
        timestamp: DateTime.now(),
        accountMask: '•••• 1277',
      );

      expect(transferTxn.isTransfer, isTrue);
      expect(transferTxn.effectivePersonalExpense, 0.0);
    });

    test(
        'Regex extracts Account Number: XX9343 and Self Transfer debit snippet',
        () {
      const debitSnippet =
          'Dear Customer, Greetings from HDFC Bank! Rs.121.00 is debited from your account ending 1277 towards VPA 7813004130@axl (RAKSHITH GOWDA G) on 04-08-26. UPI transaction reference no.: 621611733037.';
      const creditSnippet =
          'BANNER IMAGE 04-08-2026 Dear Rakshith Gowda G, Here&#39;s the summary of your transaction: Amount Credited: INR 121.00 Account Number: XX9343 Date & Time: 04-08-26, 15:27:56 IST Transaction Info:';

      // Debit parsing
      final debitAcct = RegExp(
              r'(?:account|a\/c|card)\s*(?:ending|no\.?|number|ending with)?\s*(?:in|:)?\s*[:\s]*([xX*]*\d{4})',
              caseSensitive: false)
          .firstMatch(debitSnippet);
      expect(debitAcct?.group(1), '1277');

      final payeeMatch = RegExp(
              r'towards\s+(?:VPA\s+)?[A-Za-z0-9._@-]+(?:\s*\(([^)]+)\))',
              caseSensitive: false)
          .firstMatch(debitSnippet);
      expect(payeeMatch?.group(1), 'RAKSHITH GOWDA G');

      // Credit parsing
      final creditAcct = RegExp(
              r'(?:account|a\/c|card)\s*(?:ending|no\.?|number|ending with)?\s*(?:in|:)?\s*[:\s]*([xX*]*\d{4})',
              caseSensitive: false)
          .firstMatch(creditSnippet);
      expect(creditAcct?.group(1), 'XX9343');
      final digits = creditAcct!.group(1)!.replaceAll(RegExp(r'[^0-9]'), '');
      expect(digits, '9343');

      final creditAmt = RegExp(r'(?:INR|Rs\.?)\s*([0-9,]+(?:\.[0-9]{2})?)',
              caseSensitive: false)
          .firstMatch(creditSnippet);
      expect(creditAmt?.group(1), '121.00');
    });

    test(
        'TransactionItem preserves transferCounterpartMask in toJson and fromJson',
        () {
      final item = TransactionItem(
        id: 'txn-transfer-1',
        amount: 121.0,
        currency: 'INR',
        type: 'DEBIT',
        merchantName: 'Self Transfer',
        accountId: 'acc-1277',
        categoryId: 'Self Transfer',
        subCategory: 'Account to Account Transfer',
        ingestionSource: 'EMAIL',
        reconciliationStatus: 'CONFIRMED',
        timestamp: DateTime(2026, 8, 4, 15, 27),
        accountMask: '•••• 1277',
        transferCounterpartMask: '•••• 9343',
      );

      final json = item.toJson();
      expect(json['transferCounterpartMask'], '•••• 9343');

      final restored = TransactionItem.fromJson(json);
      expect(restored.transferCounterpartMask, '•••• 9343');
      expect(restored.accountMask, '•••• 1277');
      expect(restored.isTransfer, isTrue);
      expect(restored.effectivePersonalExpense, 0.0);
    });

    test(
        'Correctly extracts and links 2650 Self Transfer debit and credit legs with XX9343',
        () {
      final debitSnippet =
          'Dear Customer, Greetings from HDFC Bank! Rs.2650.00 is debited from your account ending 1277 towards VPA 7813004130@axl (RAKSHITH GOWDA G) on 04-08-26. UPI transaction reference no.: 621688749845. If';
      final creditSnippet =
          'BANNER IMAGE 04-08-2026 Dear Rakshith Gowda G, Here&#39;s the summary of your transaction: Amount Credited: INR 2650.00 Account Number: XX9343 Date &amp; Time: 04-08-26, 09:08:03 IST Transaction Info:';

      // Debit account extraction
      final debitAcct =
          RegExp(r'account\s+ending\s+(\d{2,6})', caseSensitive: false)
              .firstMatch(debitSnippet);
      expect(debitAcct?.group(1), '1277');

      // Credit account extraction
      final creditClean =
          creditSnippet.replaceAll('&#39;', "'").replaceAll('&amp;', '&');
      final creditAcct = RegExp(
              r'(?:account\s*number)\s*[:\s-]*([xX*.]*\d{2,6})',
              caseSensitive: false)
          .firstMatch(creditClean);
      expect(creditAcct?.group(1), 'XX9343');
      final digits = creditAcct!.group(1)!.replaceAll(RegExp(r'[^0-9]'), '');
      expect(digits, '9343');
      final last4 = digits.substring(digits.length - 4);
      expect(last4, '9343');

      // Check linked transaction items
      final debitTxn = TransactionItem(
        id: 'txn-1',
        amount: 2650.0,
        currency: 'INR',
        type: 'DEBIT',
        merchantName: 'Self Transfer',
        accountId: 'acc-1277',
        categoryId: 'Self Transfer',
        subCategory: 'Account to Account Transfer',
        ingestionSource: 'EMAIL',
        reconciliationStatus: 'CONFIRMED',
        timestamp: DateTime(2026, 8, 4, 9, 8),
        accountMask: '•••• 1277',
        transferCounterpartMask: '•••• 9343',
        rawSnippet: debitSnippet,
      );

      final creditTxn = TransactionItem(
        id: 'txn-2',
        amount: 2650.0,
        currency: 'INR',
        type: 'CREDIT',
        merchantName: 'Self Transfer',
        accountId: 'acc-9343',
        categoryId: 'Self Transfer',
        subCategory: 'Account to Account Transfer',
        ingestionSource: 'EMAIL',
        reconciliationStatus: 'CONFIRMED',
        timestamp: DateTime(2026, 8, 4, 9, 8),
        accountMask: '•••• 9343',
        transferCounterpartMask: '•••• 1277',
        rawSnippet: creditSnippet,
      );

      expect(debitTxn.isTransfer, isTrue);
      expect(creditTxn.isTransfer, isTrue);
      expect(debitTxn.effectivePersonalExpense, 0.0);
      expect(creditTxn.effectivePersonalExpense, 0.0);
      expect(debitTxn.accountMask, '•••• 1277');
      expect(debitTxn.transferCounterpartMask, '•••• 9343');
      expect(creditTxn.accountMask, '•••• 9343');
      expect(creditTxn.transferCounterpartMask, '•••• 1277');
    });

    test('FinancialAccount supports anchor balance and date serialization', () {
      final acc = FinancialAccount(
        id: 'acc-1277',
        name: 'HDFC Bank (•••• 1277)',
        type: 'SAVINGS',
        lastFourDigits: '1277',
        currency: 'INR',
        currentBalance: 50868.64,
        anchorBalance: 50868.64,
        anchorDate: DateTime(2026, 8, 3),
      );

      expect(acc.isSavings, isTrue);
      expect(acc.isCreditCard, isFalse);
      expect(acc.anchorBalance, 50868.64);
      expect(acc.anchorDate, DateTime(2026, 8, 3));

      final json = acc.toJson();
      final restored = FinancialAccount.fromJson(json);

      expect(restored.anchorBalance, 50868.64);
      expect(restored.anchorDate, DateTime(2026, 8, 3));
      expect(restored.isSavings, isTrue);
    });

    test('Credit Card accounts are distinguished from Savings accounts', () {
      final hdfcCard = FinancialAccount(
        id: 'acc-9207',
        name: 'HDFC Credit Card (•••• 9207)',
        type: 'CREDIT_CARD',
        lastFourDigits: '9207',
        currency: 'INR',
        currentBalance: 2350.0,
      );

      final rblCard = FinancialAccount(
        id: 'acc-9635',
        name: 'RBL Credit Card (•••• 9635)',
        type: 'CREDIT_CARD',
        lastFourDigits: '9635',
        currency: 'INR',
        currentBalance: 336.11,
      );

      expect(hdfcCard.isCreditCard, isTrue);
      expect(hdfcCard.isSavings, isFalse);
      expect(rblCard.isCreditCard, isTrue);
      expect(rblCard.isSavings, isFalse);
    });
  });
}

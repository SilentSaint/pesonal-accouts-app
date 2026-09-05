import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/gmail_scan_service.dart';
import '../services/entity_service.dart';
import '../services/backend_api_service.dart';
import '../domain/transaction_item.dart';

class EmailSettingsScreen extends StatefulWidget {
  const EmailSettingsScreen({
    super.key,
    this.authService,
    this.gmailScanService,
  });

  final AuthService? authService;
  final GmailScanService? gmailScanService;

  @override
  State<EmailSettingsScreen> createState() => _EmailSettingsScreenState();
}

class _EmailSettingsScreenState extends State<EmailSettingsScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _queryController = TextEditingController();
  final List<Map<String, String>> _linkedAccounts = [];
  bool _isScanning = false;

  AuthService get _auth => widget.authService ?? AuthService();
  GmailScanService get _gmailScan =>
      widget.gmailScanService ?? GmailScanService();

  @override
  void initState() {
    super.initState();
    _auth.addListener(_loadOAuthLinkedAccount);
    _loadOAuthLinkedAccount();
  }

  @override
  void dispose() {
    _auth.removeListener(_loadOAuthLinkedAccount);
    _emailController.dispose();
    _queryController.dispose();
    super.dispose();
  }

  /// Pre-populate the linked accounts list with the OAuth-verified Gmail.
  void _loadOAuthLinkedAccount() {
    final auth = _auth;
    if (auth.isAuthenticated && auth.userEmail.isNotEmpty && mounted) {
      setState(() {
        _linkedAccounts.removeWhere((a) => a['type'] == 'GOOGLE_OAUTH');
        _linkedAccounts.insert(0, {
          'email': auth.userEmail,
          'status': auth.hasGmailAccess ? 'GMAIL_READONLY' : 'OAUTH_ONLY',
          'linkedAt': 'via Google Sign-In',
          'type': 'GOOGLE_OAUTH',
        });
      });
    }
  }

  void _linkNewEmail() {
    final text = _emailController.text.trim();
    if (text.isEmpty || !text.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email address'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    setState(() {
      _linkedAccounts.add({
        'email': text,
        'status': 'WEBHOOK_ACTIVE',
        'linkedAt': DateTime.now().toString().split(' ')[0],
        'type': 'MANUAL',
      });
      _emailController.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$text linked for bank email ingestion.'),
        backgroundColor: const Color(0xFF22C55E),
      ),
    );
  }

  Future<void> _scanInboxNow() async {
    final auth = _auth;

    // If gmail.readonly has not been granted yet, prompt user to grant it
    if (!auth.hasGmailAccess) {
      final grant = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.lock_outline, color: Color(0xFFFBBF24), size: 24),
              SizedBox(width: 10),
              Text('Gmail Permission Required',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
          content: const Text(
            'To scan your mailbox for bank transaction alerts and credit card statements, '
            'Google requires your permission to read emails (gmail.readonly).\n\n'
            'Your emails are processed locally and securely.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB)),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Grant Permission',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (grant != true) return;

      final success = await auth.requestGmailAccess();
      if (!mounted) return;
      _loadOAuthLinkedAccount();

      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Gmail access was not granted. Please check the box on the Google prompt.'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
        return;
      }
    }

    setState(() => _isScanning = true);
    final result =
        await _gmailScan.scanInbox(query: _queryController.text.trim());
    if (!mounted) return;
    setState(() => _isScanning = false);

    _showScanResultsDialog(result);
  }

  void _showScanResultsDialog(GmailScanResult result) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(
              result.success ? Icons.mark_email_read : Icons.error_outline,
              color: result.success
                  ? const Color(0xFF10B981)
                  : const Color(0xFFEF4444),
              size: 24,
            ),
            const SizedBox(width: 10),
            Text(
              result.success ? 'Inbox Scan Results' : 'Scan Failed',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!result.success) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0x22EF4444),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    result.error ?? 'Unknown error during scan',
                    style:
                        const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13),
                  ),
                ),
              ] else ...[
                // Stats Card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Text('${result.emailsScanned}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          const Text('Emails Checked',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 11)),
                        ],
                      ),
                      Container(width: 1, height: 30, color: Colors.white12),
                      Column(
                        children: [
                          Text(
                            '${result.transactionCandidates.length}',
                            style: const TextStyle(
                                color: Color(0xFF34D399),
                                fontSize: 18,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          const Text('Transactions Found',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (result.transactionCandidates.isEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.0),
                    child: Text(
                      'No bank alert or statement emails found in your recent messages.\n\n'
                      'Tips:\n'
                      '• Ensure your bank sends transaction alerts to this email.\n'
                      '• Try searching for your specific bank name (e.g. HDFC, ICICI, SBI) using the search box above.',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 12, height: 1.4),
                    ),
                  ),
                ] else ...[
                  const Text('Discovered Transactions:',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: result.transactionCandidates.length,
                      itemBuilder: (ctx, i) {
                        final item = result.transactionCandidates[i];
                        final amt = (item['amount'] as num?)?.toDouble() ?? 0.0;
                        final isCredit = item['type'] == 'CREDIT';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isCredit
                                    ? Icons.arrow_downward
                                    : Icons.arrow_upward,
                                color: isCredit
                                    ? const Color(0xFF34D399)
                                    : const Color(0xFFF87171),
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['merchantName'] ??
                                          item['subject'] ??
                                          'Bank Alert',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if ((item['snippet'] as String?)
                                            ?.isNotEmpty ==
                                        true)
                                      Text(
                                        item['snippet'],
                                        style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 11),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                amt > 0
                                    ? '₹${amt.toStringAsFixed(2)}'
                                    : 'Review',
                                style: TextStyle(
                                  color: isCredit
                                      ? const Color(0xFF34D399)
                                      : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close', style: TextStyle(color: Colors.white54)),
          ),
          if (!result.success && result.requiresReconnect)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
              ),
              onPressed: () async {
                Navigator.of(ctx).pop();
                await _reconnectGmail();
              },
              child: const Text(
                'Reconnect Gmail',
                style: TextStyle(color: Colors.white),
              ),
            ),
          if (result.success && result.transactionCandidates.isNotEmpty)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981)),
              onPressed: () async {
                Navigator.of(ctx).pop();
                await _importScanCandidates(result.transactionCandidates);
              },
              child: Text(
                'Import ${result.transactionCandidates.length} to Dashboard',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _reconnectGmail() async {
    final connected = await _auth.requestGmailAccess();
    if (!mounted) return;
    _loadOAuthLinkedAccount();
    if (!connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Gmail access was not granted. You can reconnect when ready.',
          ),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }
    await _scanInboxNow();
  }

  Future<void> _importScanCandidates(
      List<Map<String, dynamic>> candidates) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('saved_pending_txns');
      final List<dynamic> existing = raw != null ? jsonDecode(raw) : [];
      final rawRecent = prefs.getString('saved_recent_txns');
      final List<dynamic> recent =
          rawRecent != null ? jsonDecode(rawRecent) : [];

      await EntityService().ensureLoaded();
      int imported = 0;
      int autoAccounted = 0;
      for (final c in candidates) {
        final cleanMerchant = (c['merchantName'] as String?)?.trim();
        final subject = (c['subject'] as String?)?.trim();
        final merchantToUse = (cleanMerchant != null &&
                cleanMerchant.isNotEmpty &&
                cleanMerchant != 'Bank Alert')
            ? cleanMerchant
            : (subject != null && subject.isNotEmpty ? subject : 'Bank Alert');

        final msgId = (c['messageId'] as String?)?.trim();
        final stableId = (msgId != null && msgId.isNotEmpty)
            ? 'txn-gmail-$msgId'
            : 'txn-gmail-${DateTime.now().millisecondsSinceEpoch}-$imported';
        final upiId = c['upiId'] as String?;
        final accountMask = c['accountMask'] as String?;

        // Skip if already in pending
        final alreadyPending = existing.any((e) {
          final id = e['id'] as String?;
          return id == stableId ||
              (msgId != null &&
                  msgId.isNotEmpty &&
                  id?.contains(msgId) == true);
        });
        if (alreadyPending) continue;

        // Skip if already confirmed in recent
        final alreadyConfirmed = recent.any((r) {
          final id = r['id'] as String?;
          final ref = r['referenceNumber'] as String?;
          return id == stableId ||
              (msgId != null &&
                  msgId.isNotEmpty &&
                  id?.contains(msgId) == true) ||
              (upiId != null && upiId.isNotEmpty && ref == upiId);
        });
        if (alreadyConfirmed) continue;

        // Auto-account if merchant alias exists!
        final matchedEntity = EntityService().matchEntity(
          upiId: upiId,
          rawName: cleanMerchant ?? merchantToUse,
          accountMask: accountMask,
        );

        if (matchedEntity != null) {
          final autoTxn = {
            'id': stableId,
            'amount': (c['amount'] as num?)?.toDouble() ?? 0.0,
            'currency': 'INR',
            'type': c['type'] ?? 'DEBIT',
            'merchantName': matchedEntity.name,
            'accountId': 'acc-gmail',
            'categoryId': matchedEntity.defaultCategory ?? 'General Expenses',
            'subCategory': matchedEntity.defaultSubCategory,
            'ingestionSource': 'EMAIL',
            'reconciliationStatus': 'AUTO_CONFIRMED',
            'timestamp':
                DateTime.tryParse(c['date'] ?? '')?.millisecondsSinceEpoch ??
                    DateTime.now().millisecondsSinceEpoch,
            'accountMask': accountMask,
            'referenceNumber': upiId,
            'rawSnippet': c['snippet'],
          };
          recent.insert(0, autoTxn);
          if (AuthService().isAuthenticated) {
            BackendApiService()
                .createTransaction(TransactionItem.fromJson(autoTxn));
          }
          autoAccounted++;
          continue;
        }

        final txn = {
          'id': stableId,
          'amount': (c['amount'] as num?)?.toDouble() ?? 0.0,
          'currency': 'INR',
          'type': c['type'] ?? 'DEBIT',
          'merchantName': merchantToUse,
          'accountId': 'acc-gmail',
          'categoryId': c['category'] ?? 'General Expenses',
          'ingestionSource': 'EMAIL',
          'reconciliationStatus': 'NEEDS_REVIEW',
          'timestamp':
              DateTime.tryParse(c['date'] ?? '')?.millisecondsSinceEpoch ??
                  DateTime.now().millisecondsSinceEpoch,
          'accountMask': accountMask,
          'referenceNumber': upiId,
          'rawSnippet': c['snippet'],
        };
        existing.insert(0, txn);
        imported++;
      }

      await prefs.setString('saved_pending_txns', jsonEncode(existing));
      if (autoAccounted > 0) {
        await prefs.setString('saved_recent_txns', jsonEncode(recent));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Imported $imported transactions to Dashboard! Return to Dashboard to review.'),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to import: $e'),
              backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  void _simulateStatementWebhookIngestion() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Simulate Statement Webhook Ingestion',
            style: TextStyle(color: Colors.white)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Payload incoming from email webhook:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            SizedBox(height: 8),
            Text(
              '• Card: HDFC Regalia (Ending 4321)\n• Statement Total: ₹34,500.00\n• Minimum Due: ₹2,000.00\n• Due Date: 05/09/2026\n• Transactions: 14 parsed (12 new, 2 auto-merged duplicates)',
              style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1)),
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'Statement Webhook Ingested: 14 txns processed, 1 Bill Statement reconciled!'),
                  backgroundColor: Color(0xFF22C55E),
                ),
              );
            },
            child: const Text('Execute Webhook Ingest',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Linked Email Accounts',
            style: TextStyle(color: Colors.white)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Statement Webhook Ingest Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.picture_as_pdf,
                      color: Color(0xFFA5B4FC), size: 32),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Credit Card E-Statements',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Webhooks automatically extract bill totals, due dates & itemized transactions.',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFFA5B4FC)),
                    ),
                    onPressed: _simulateStatementWebhookIngestion,
                    child: const Text('Test Webhook',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Link Financial Email Account',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Enter your financial email address to receive real-time push webhooks for bank alerts and bill statements.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _emailController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'your.email@domain.com',
                            hintStyle: const TextStyle(color: Colors.white38),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: Colors.white24),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: _linkNewEmail,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Link Account',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Active Linked Accounts',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _linkedAccounts.isEmpty
                  ? const Center(
                      child: Text(
                        'Sign in with Google to automatically link your Gmail for bank email ingestion.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _linkedAccounts.length,
                      itemBuilder: (context, index) {
                        final item = _linkedAccounts[index];
                        final isOAuth = item['type'] == 'GOOGLE_OAUTH';
                        final status = item['status']!;
                        final statusColor = isOAuth &&
                                status == 'GMAIL_READONLY'
                            ? const Color(
                                0xFF4ADE80) // green — gmail.readonly active
                            : isOAuth
                                ? const Color(
                                    0xFFFBBF24) // amber — signed in but no gmail access
                                : const Color(
                                    0xFF38BDF8); // blue — manual/webhook

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isOAuth
                                  ? const Color(0xFF4285F4)
                                      .withValues(alpha: 0.3)
                                  : Colors.white12,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        isOAuth
                                            ? Icons.verified_user
                                            : Icons.mark_email_read,
                                        color: isOAuth
                                            ? const Color(0xFF4285F4)
                                            : const Color(0xFF38BDF8),
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item['email']!,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14),
                                          ),
                                          Text(
                                            isOAuth
                                                ? 'Verified via Google OAuth'
                                                : 'Linked: ${item['linkedAt']}',
                                            style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 11),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color:
                                          statusColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      status,
                                      style: TextStyle(
                                          color: statusColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              if (isOAuth) ...[
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _queryController,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 13),
                                  decoration: InputDecoration(
                                    hintText:
                                        'Filter query (e.g. HDFC, ICICI, statement, UPI)',
                                    hintStyle: const TextStyle(
                                        color: Colors.white38, fontSize: 12),
                                    prefixIcon: const Icon(Icons.search,
                                        color: Colors.white38, size: 18),
                                    filled: true,
                                    fillColor: const Color(0xFF0F172A),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                          color: Colors.white12),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF1E3A5F),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 11),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                    ),
                                    icon: _isScanning
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white70))
                                        : const Icon(Icons.mark_email_read,
                                            size: 16),
                                    label: Text(
                                      _isScanning
                                          ? 'Scanning Mailbox…'
                                          : 'Scan Inbox for Bank Alerts',
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    onPressed:
                                        _isScanning ? null : _scanInboxNow,
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
      ),
    );
  }
}

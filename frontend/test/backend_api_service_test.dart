import 'dart:async';
import 'dart:convert';

import 'package:automatic_expense_tracker/domain/transaction_item.dart';
import 'package:automatic_expense_tracker/services/backend_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('SerialRequestQueue runs mutations one at a time', () async {
    final queue = SerialRequestQueue();
    final started = <int>[];
    final releaseFirst = Completer<void>();

    final first = queue.run(() async {
      started.add(1);
      await releaseFirst.future;
    });
    final second = queue.run(() async {
      started.add(2);
    });

    await Future<void>.delayed(Duration.zero);
    expect(started, [1]);

    releaseFirst.complete();
    await Future.wait([first, second]);
    expect(started, [1, 2]);
  });

  test(
      'createTransaction durably submits a command and removes it after completion',
      () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <http.Request>[];
    final service = BackendApiService.forTesting(
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'POST') {
          return http.Response(
            '{"id":"txn-manual-1724911200000","status":"PENDING"}',
            202,
          );
        }
        return http.Response(
          '{"id":"txn-manual-1724911200000","status":"COMPLETED"}',
          200,
        );
      }),
      preferences: SharedPreferences.getInstance,
      wait: (_) async {},
    );

    final result = await service.createTransaction(_transaction());

    expect(result, isTrue);
    expect(requests.map((request) => request.url.path), [
      '/v2/transactions',
      '/v2/transactions/txn-manual-1724911200000/status',
    ]);
    expect(jsonDecode(requests.first.body)['timestamp'], 1724911200000);
    final preferences = await SharedPreferences.getInstance();
    expect(
      jsonDecode(preferences
          .getString(BackendApiService.durableTransactionCommandsKey)!),
      isEmpty,
    );
  });

  test('createTransaction submits every field in an edited review result',
      () async {
    SharedPreferences.setMockInitialValues({});
    Map<String, dynamic>? submitted;
    final service = BackendApiService.forTesting(
      client: MockClient((request) async {
        submitted = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'id': submitted!['id'], 'status': 'COMPLETED'}),
          202,
        );
      }),
      preferences: SharedPreferences.getInstance,
    );
    final edited = TransactionItem(
      id: 'txn-review-00000001',
      amount: 913.42,
      currency: 'INR',
      type: 'TRANSFER',
      merchantName: 'Green Market',
      accountId: 'acc-1234',
      categoryId: 'Groceries',
      subCategory: 'Fruits & Vegetables',
      ingestionSource: 'MANUAL',
      reconciliationStatus: 'CONFIRMED',
      timestamp: DateTime.utc(2026, 8, 29, 6),
      netPersonalExpense: 900,
      accountMask: '•••• 1234',
      referenceNumber: 'upi-12345678',
      rawSnippet: 'edited receipt',
      transferCounterpartMask: '•••• 9876',
    );

    expect(await service.createTransaction(edited), isTrue);
    expect(submitted, edited.toJson());
  });

  test(
      'retains a durable command id when submission times out and reuses it on retry',
      () async {
    SharedPreferences.setMockInitialValues({});
    var posts = 0;
    final submittedIds = <String>[];
    final service = BackendApiService.forTesting(
      client: MockClient((request) async {
        if (request.method == 'POST') {
          submittedIds.add(jsonDecode(request.body)['id'] as String);
          posts++;
          if (posts == 1) {
            return Completer<http.Response>().future;
          }
          return http.Response(
            jsonEncode({'id': submittedIds.last, 'status': 'COMPLETED'}),
            202,
          );
        }
        throw StateError(
            'No status polling is expected for a terminal response');
      }),
      preferences: SharedPreferences.getInstance,
      wait: (_) async {},
      requestTimeout: Duration.zero,
    );

    expect(await service.createTransaction(_transaction(id: 'short')), isFalse);
    final preferences = await SharedPreferences.getInstance();
    final storedId = jsonDecode(
      preferences.getString(BackendApiService.durableTransactionCommandsKey)!,
    )['short'] as String;
    expect(storedId, matches(RegExp(r'^cmd-[a-f0-9]{64}$')));

    expect(await service.createTransaction(_transaction(id: 'short')), isTrue);
    expect(submittedIds, [storedId, storedId]);
    expect(
      jsonDecode(preferences
          .getString(BackendApiService.durableTransactionCommandsKey)!),
      isEmpty,
    );
  });

  test('batchCreateTransactions submits each durable command separately',
      () async {
    SharedPreferences.setMockInitialValues({});
    final bodies = <Map<String, dynamic>>[];
    final service = BackendApiService.forTesting(
      client: MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode(
              {'id': jsonDecode(request.body)['id'], 'status': 'COMPLETED'}),
          202,
        );
      }),
      preferences: SharedPreferences.getInstance,
      wait: (_) async {},
    );

    final result = await service.batchCreateTransactions([
      _transaction(),
      _transaction(id: 'txn-manual-1724911200001'),
    ]);

    expect(result, isTrue);
    expect(bodies, hasLength(2));
    expect(bodies.map((body) => body['id']), [
      'txn-manual-1724911200000',
      'txn-manual-1724911200001',
    ]);
  });

  test(
      'confirmReviewedTransaction persists the transaction then learns its payee category rule',
      () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <http.Request>[];
    final reviewed = _transaction().copyWith(
      categoryId: 'Food & Dining',
      subCategory: 'Tea & Snacks',
      merchantName: 'Saira’s tea stall',
      reconciliationStatus: 'CONFIRMED',
    );
    final service = BackendApiService.forTesting(
      client: MockClient((request) async {
        requests.add(request);
        switch (request.method) {
          case 'POST':
            return http.Response(
              jsonEncode({'id': reviewed.id, 'status': 'PENDING'}),
              202,
            );
          case 'GET':
            return http.Response(
              jsonEncode({'id': reviewed.id, 'status': 'COMPLETED'}),
              200,
            );
          case 'PUT':
            return http.Response(
              jsonEncode({
                'id': reviewed.id,
                'categoryId': 'Food & Dining',
                'subCategory': 'Tea & Snacks',
              }),
              200,
            );
        }
        throw StateError('Unexpected request: ${request.method}');
      }),
      preferences: SharedPreferences.getInstance,
      wait: (_) async {},
    );

    final confirmed = await service.confirmReviewedTransaction(reviewed);

    expect(confirmed?.toJson(), reviewed.toJson());
    expect(requests.map((request) => request.method), ['POST', 'GET', 'PUT']);
    expect(requests.last.url.path,
        '/v2/transactions/txn-manual-1724911200000/category');
    expect(jsonDecode(requests.last.body), {
      'categoryId': 'Food & Dining',
      'subCategory': 'Tea & Snacks',
      'payeeNickname': 'Saira’s tea stall',
    });
  });

  test(
      'confirmReviewedTransaction does not learn a category when durable persistence fails',
      () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <http.Request>[];
    final reviewed = _transaction().copyWith(
      categoryId: 'Food & Dining',
      subCategory: 'Tea & Snacks',
    );
    final service = BackendApiService.forTesting(
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'POST') {
          return http.Response(
            jsonEncode({'id': reviewed.id, 'status': 'PENDING'}),
            202,
          );
        }
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'id': reviewed.id,
              'status': 'FAILED',
              'failureReason': 'Transaction could not be processed',
            }),
            200,
          );
        }
        throw StateError('Category learning must not run after a failed command');
      }),
      preferences: SharedPreferences.getInstance,
      wait: (_) async {},
    );

    expect(await service.confirmReviewedTransaction(reviewed), isNull);
    expect(requests.map((request) => request.method), ['POST', 'GET']);
    final preferences = await SharedPreferences.getInstance();
    expect(
      jsonDecode(preferences
          .getString(BackendApiService.durableTransactionCommandsKey)!),
      isEmpty,
    );
  });

  test(
      'loads server-authoritative review candidates with their canonical record',
      () async {
    final candidate = _transaction(id: 'txn-email-001').copyWith(
      reconciliationStatus: 'NEEDS_REVIEW',
      potentialDuplicateOfTransactionId: 'txn-sms-001',
    );
    final canonical = _transaction(id: 'txn-sms-001').copyWith(
      ingestionSource: 'SMS',
      reconciliationStatus: 'CONFIRMED',
      ingestionSources: const ['SMS'],
    );
    final service = BackendApiService.forTesting(
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v2/reconciliation/review-queue');
        return http.Response(
            jsonEncode([
              {'candidate': candidate.toJson(), 'canonical': canonical.toJson()}
            ]),
            200);
      }),
      preferences: SharedPreferences.getInstance,
    );

    final queue = await service.fetchReconciliationReviewQueue();

    expect(queue?.pendingTransactions.single.id, 'txn-email-001');
    expect(queue?.pendingTransactions.single.potentialDuplicateOfTransactionId,
        'txn-sms-001');
    expect(queue?.canonicalTransactions.single.id, 'txn-sms-001');
  });

  test('merges a candidate through the authoritative reconciliation endpoint',
      () async {
    final canonical = _transaction(id: 'txn-sms-001').copyWith(
      ingestionSource: 'SMS',
      reconciliationStatus: 'AUTO_MERGED',
      ingestionSources: const ['EMAIL', 'SMS'],
    );
    final service = BackendApiService.forTesting(
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v2/reconciliation/txn-email-001/merge');
        expect(jsonDecode(request.body),
            {'canonicalTransactionId': 'txn-sms-001'});
        return http.Response(jsonEncode(canonical.toJson()), 200);
      }),
      preferences: SharedPreferences.getInstance,
    );

    final merged = await service.mergeReconciledDuplicate(
      canonicalTransactionId: 'txn-sms-001',
      duplicateTransactionId: 'txn-email-001',
    );

    expect(merged?.id, 'txn-sms-001');
    expect(merged?.ingestionSources, ['EMAIL', 'SMS']);
  });

  test('fetchTransactions reloads and maps every paginated history response',
      () async {
    final requestedCursors = <String?>[];
    final service = BackendApiService.forTesting(
      client: MockClient((request) async {
        requestedCursors.add(request.url.queryParameters['cursor']);
        if (requestedCursors.length == 1) {
          return http.Response(
            jsonEncode({
              'items': [_transaction().toJson()],
              'nextCursor': 'next-page',
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'items': [
              _transaction(id: 'txn-manual-1724911200001').toJson(),
            ],
          }),
          200,
        );
      }),
      preferences: SharedPreferences.getInstance,
    );

    final transactions = await service.fetchTransactions();

    expect(requestedCursors, [null, 'next-page']);
    expect(
      transactions.map((transaction) => transaction.id),
      ['txn-manual-1724911200000', 'txn-manual-1724911200001'],
    );
  });

  test('fetches selected server analytics and downloads real report bytes',
      () async {
    final requestedPaths = <Uri>[];
    final service = BackendApiService.forTesting(
      client: MockClient((request) async {
        requestedPaths.add(request.url);
        if (request.url.path.endsWith('/analytics/export')) {
          return http.Response.bytes(
            [0x25, 0x50, 0x44, 0x46],
            200,
            headers: {'content-type': 'application/pdf'},
          );
        }
        return http.Response(
          jsonEncode({
            'month': '2026-08',
            'currency': 'INR',
            'transactionCount': 2,
            'cashFlow': {
              'income': 1000,
              'spending': 300,
              'netPersonalExpense': 250,
              'netSavings': 750,
            },
            'categoryTotals': [
              {'categoryId': 'Dining', 'total': 250, 'percentageOfTotal': 100}
            ],
            'spendingTrend': [
              {
                'date': '2026-08-01',
                'income': 1000,
                'spending': 0,
                'netPersonalExpense': 0,
              }
            ],
            'aiInsights': ['Dining is the largest category.'],
            'insightSource': 'SERVER_DERIVED_FALLBACK',
          }),
          200,
        );
      }),
      preferences: SharedPreferences.getInstance,
    );

    final report = await service.fetchAnalyticsReport(month: '2026-08');
    final export = await service.exportAnalyticsReport(
      month: '2026-08',
      format: 'pdf',
    );

    expect(report.cashFlow.netPersonalExpense, 250);
    expect(report.categoryTotals.single.categoryId, 'Dining');
    expect(export.bytes, [0x25, 0x50, 0x44, 0x46]);
    expect(export.filename, 'financial-report-2026-08.pdf');
    expect(requestedPaths.map((path) => path.path), [
      '/v2/analytics',
      '/api/analytics/export',
    ]);
    expect(requestedPaths.first.queryParameters, {
      'month': '2026-08',
      'currency': 'INR',
    });
    expect(requestedPaths.last.queryParameters['format'], 'pdf');
  });

  test('fetches a deterministic analytics envelope and paginated evidence from Java routes',
      () async {
    final requests = <Uri>[];
    final service = BackendApiService.forTesting(
      client: MockClient((request) async {
        requests.add(request.url);
        if (request.url.path.endsWith('/evidence')) {
          return http.Response(jsonEncode({
            'value': {
              'items': [
                {
                  'id': 'txn-1',
                  'amount': 120,
                  'currency': 'INR',
                  'type': 'DEBIT',
                  'merchantName': 'Coffee Shop',
                  'accountId': 'account-1',
                  'categoryId': 'Dining',
                  'timestamp': '2026-08-02T10:00:00',
                  'netPersonalExpense': 120,
                }
              ],
              'nextCursor': 'next-page',
            }
          }), 200);
        }
        return http.Response(jsonEncode({
          'classification': 'FACT',
          'asOf': '2026-08-31T00:00:00Z',
          'formula': {'id': 'spending-analytics', 'version': '1.0.0'},
          'warnings': ['INCOMPLETE_PERIOD'],
          'value': {
            'currentPeriod': {
              'start': '2026-08-01',
              'end': '2026-08-31',
              'total': {'amount': 120, 'currency': 'INR'},
              'transactionCount': 1,
            },
            'previousPeriod': {
              'start': '2026-07-01',
              'end': '2026-07-31',
              'total': {'amount': 100, 'currency': 'INR'},
              'transactionCount': 1,
            },
            'categoryBreakdown': [
              {'key': 'Dining', 'total': {'amount': 120, 'currency': 'INR'}}
            ],
          },
        }), 200);
      }),
      preferences: SharedPreferences.getInstance,
    );

    final report = await service.fetchAnalyticsReport(month: '2026-08');
    final evidence = await service.fetchAnalyticsEvidence(
      month: '2026-08',
      currency: 'INR',
    );

    expect(report.isSpendingAnalytics, isTrue);
    expect(report.cashFlow.netPersonalExpense, 120);
    expect(report.formulaId, 'spending-analytics');
    expect(report.warnings, ['INCOMPLETE_PERIOD']);
    expect(evidence.items.single.id, 'txn-1');
    expect(evidence.nextCursor, 'next-page');
    expect(requests.map((request) => request.path), [
      '/v2/analytics',
      '/v2/analytics/evidence',
    ]);
  });
}

TransactionItem _transaction({String id = 'txn-manual-1724911200000'}) {
  return TransactionItem(
    id: id,
    amount: 125,
    currency: 'INR',
    type: 'DEBIT',
    merchantName: 'Coffee Shop',
    accountId: 'acc-1001',
    ingestionSource: 'MANUAL',
    reconciliationStatus: 'CONFIRMED',
    timestamp: DateTime.utc(2024, 8, 29, 6),
  );
}

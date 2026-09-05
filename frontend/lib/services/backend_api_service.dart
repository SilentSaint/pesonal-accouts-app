import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/analytics_report.dart';
import '../domain/financial_context_item.dart';
import '../domain/financial_account.dart';
import '../domain/financial_goal.dart';
import '../domain/income_source.dart';
import '../domain/transaction_item.dart';
import 'api_config.dart';
import 'auth_service.dart';
import 'reconciliation_review_queue.dart';

class SerialRequestQueue {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (_, __) {});
    return result;
  }
}

class BackendApiService {
  static final BackendApiService _instance = BackendApiService._internal();
  factory BackendApiService() => _instance;
  BackendApiService._internal()
      : _client = http.Client(),
        _preferences = SharedPreferences.getInstance,
        _wait = Future<void>.delayed,
        _requestTimeout = const Duration(seconds: 5),
        _maxStatusPolls = 20;

  BackendApiService.forTesting({
    required http.Client client,
    required Future<SharedPreferences> Function() preferences,
    Future<void> Function(Duration) wait = Future<void>.delayed,
    Duration requestTimeout = const Duration(seconds: 5),
    int maxStatusPolls = 20,
  })  : _client = client,
        _preferences = preferences,
        _wait = wait,
        _requestTimeout = requestTimeout,
        _maxStatusPolls = maxStatusPolls;

  final SerialRequestQueue _mutationQueue = SerialRequestQueue();
  final http.Client _client;
  final Future<SharedPreferences> Function() _preferences;
  final Future<void> Function(Duration) _wait;
  final Duration _requestTimeout;
  final int _maxStatusPolls;
  String? _lastTransactionError;

  static const durableTransactionCommandsKey =
      'durable_transaction_command_ids';
  static const _commandIdPattern = r'^[A-Za-z0-9][A-Za-z0-9_-]{7,127}$';
  static const _statusPollInterval = Duration(milliseconds: 500);

  String? get lastTransactionError => _lastTransactionError;

  String get _baseUrl => ApiConfig.baseUrl;
  String get _transactionCommandBaseUrl => _baseUrl.endsWith('/api')
      ? _baseUrl.substring(0, _baseUrl.length - '/api'.length)
      : _baseUrl;

  Map<String, String> get _headers {
    final auth = AuthService();
    return auth.withBackendAuthorization({
      'Content-Type': 'application/json',
      // Google ID token — backend verifies this against Google's tokeninfo endpoint
      if (auth.idToken != null) 'Authorization': 'Bearer ${auth.idToken}',
      // Gmail OAuth access token — used by /api/gmail/scan to call Gmail API
      if (auth.gmailAccessToken != null)
        'X-Gmail-Token': auth.gmailAccessToken!,
    });
  }

  Future<List<FinancialAccount>> fetchAccounts() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/accounts'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final List<dynamic> list = jsonDecode(response.body);
        return list
            .map((item) =>
                FinancialAccount.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('BackendApiService.fetchAccounts error: $e');
    }
    return [];
  }

  Future<AnalyticsReport> fetchAnalyticsReport({
    required String month,
    String currency = 'INR',
  }) async {
    final response = await _financialAnalyticsRequest(
      '/v2/analytics',
      month: month,
      currency: currency,
    );
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('Analytics response is invalid');
      }
      return AnalyticsReport.fromJson(Map<String, dynamic>.from(decoded));
    } on FormatException catch (error) {
      throw BackendApiException('Analytics response could not be read: $error');
    }
  }

  Future<AnalyticsEvidencePage> fetchAnalyticsEvidence({
    required String month,
    required String currency,
    String? cursor,
    String? asOf,
  }) async {
    final response = await _financialAnalyticsRequest(
      '/v2/analytics/evidence',
      month: month,
      currency: currency,
      extraParameters: {
        if (cursor != null) 'cursor': cursor,
        if (asOf != null) 'asOf': asOf,
      },
    );
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('Evidence response is invalid');
      }
      return AnalyticsEvidencePage.fromJson(Map<String, dynamic>.from(decoded));
    } on FormatException catch (error) {
      throw BackendApiException('Evidence response could not be read: $error');
    }
  }

  Future<AnalyticsExport> exportAnalyticsReport({
    required String month,
    required String format,
    String currency = 'INR',
  }) async {
    final normalizedFormat = format.toLowerCase();
    if (normalizedFormat != 'csv' && normalizedFormat != 'pdf') {
      throw ArgumentError.value(format, 'format', 'must be csv or pdf');
    }
    final response = await _analyticsRequest(
      '/analytics/export',
      month: month,
      currency: currency,
      extraParameters: {'format': normalizedFormat},
    );
    return AnalyticsExport(
      bytes: response.bodyBytes,
      filename: 'financial-report-$month.$normalizedFormat',
      mimeType: normalizedFormat == 'csv'
          ? 'text/csv; charset=utf-8'
          : 'application/pdf',
    );
  }

  Future<http.Response> _analyticsRequest(
    String path, {
    required String month,
    required String currency,
    Map<String, String> extraParameters = const {},
  }) async {
    try {
      final response = await _client
          .get(
            Uri.parse('$_baseUrl$path').replace(
              queryParameters: {
                'month': month,
                'currency': currency,
                ...extraParameters,
              },
            ),
            headers: _headers,
          )
          .timeout(_requestTimeout);
      if (response.statusCode != 200) {
        throw BackendApiException(
          'The report service returned ${response.statusCode}. Please try again.',
        );
      }

      return response;
    } on BackendApiException {
      rethrow;
    } catch (error) {
      throw BackendApiException('The report service is unavailable: $error');
    }
  }

  Future<http.Response> _financialAnalyticsRequest(
    String path, {
    required String month,
    required String currency,
    Map<String, String> extraParameters = const {},
  }) async {
    try {
      final response = await _client
          .get(
            Uri.parse('$_transactionCommandBaseUrl$path').replace(
              queryParameters: {
                'month': month,
                'currency': currency,
                ...extraParameters,
              },
            ),
            headers: _headers,
          )
          .timeout(_requestTimeout);
      if (response.statusCode != 200) {
        throw BackendApiException(
          'The financial analytics service returned ${response.statusCode}. Please try again.',
        );
      }
      return response;
    } on BackendApiException {
      rethrow;
    } catch (error) {
      throw BackendApiException(
          'The financial analytics service is unavailable: $error');
    }
  }

  Future<bool> createAccount(FinancialAccount account) async {
    return _mutationQueue.run(() async {
      try {
        final response = await http
            .post(
              Uri.parse('$_baseUrl/accounts'),
              headers: _headers,
              body: jsonEncode(account.toJson()),
            )
            .timeout(const Duration(seconds: 5));
        return response.statusCode == 200 || response.statusCode == 201;
      } catch (e) {
        debugPrint('BackendApiService.createAccount error: $e');
        return false;
      }
    });
  }

  Future<FinancialContextList> fetchFinancialContext({
    DateTime? asOf,
  }) async {
    final response = await _financialContextRequest(
      'GET',
      '/v2/financial-context',
      asOf: asOf,
    );
    if (response.statusCode != 200) {
      throw BackendApiException(
          'Financial context service returned ${response.statusCode}. Please try again.');
    }
    try {
      return FinancialContextList.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body) as Map));
    } catch (error) {
      throw BackendApiException(
          'Financial context response could not be read: $error');
    }
  }

  Future<FinancialContextItem> createFinancialContext(
      FinancialContextItem item) async {
    return _financialContextMutation(
        'POST', '/v2/financial-context', item.toRequestJson());
  }

  Future<FinancialContextItem> updateFinancialContext(
      FinancialContextItem item) async {
    final payload = item.toRequestJson(includeProvenance: false)
      ..remove('type');
    return _financialContextMutation(
      'PUT',
      '/v2/financial-context/${Uri.encodeComponent(item.id)}',
      payload,
    );
  }

  Future<FinancialContextItem> deactivateFinancialContext(String id) async {
    return _financialContextMutation(
      'POST',
      '/v2/financial-context/${Uri.encodeComponent(id)}/deactivate',
      const {},
    );
  }

  Future<void> deleteFinancialContext(String id) async {
    final response = await _financialContextRequest(
      'DELETE',
      '/v2/financial-context/${Uri.encodeComponent(id)}',
    );
    if (response.statusCode != 204) {
      throw BackendApiException(
          'Financial context service returned ${response.statusCode}. Please try again.');
    }
  }

  Future<FinancialContextItem> _financialContextMutation(
    String method,
    String path,
    Map<String, dynamic> payload,
  ) async {
    final response =
        await _financialContextRequest(method, path, body: payload);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw BackendApiException(
          'Financial context service returned ${response.statusCode}. Please try again.');
    }
    try {
      return FinancialContextItem.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body) as Map));
    } catch (error) {
      throw BackendApiException(
          'Financial context response could not be read: $error');
    }
  }

  Future<http.Response> _financialContextRequest(
    String method,
    String path, {
    DateTime? asOf,
    Map<String, dynamic>? body,
  }) async {
    try {
      final uri = Uri.parse('$_transactionCommandBaseUrl$path').replace(
        queryParameters:
            asOf == null ? null : {'asOf': asOf.toUtc().toIso8601String()},
      );
      final Future<http.Response> request;
      switch (method) {
        case 'GET':
          request = _client.get(uri, headers: _headers);
          break;
        case 'POST':
          request =
              _client.post(uri, headers: _headers, body: jsonEncode(body));
          break;
        case 'PUT':
          request = _client.put(uri, headers: _headers, body: jsonEncode(body));
          break;
        case 'DELETE':
          request = _client.delete(uri, headers: _headers);
          break;
        default:
          throw ArgumentError.value(method, 'method');
      }

      return await request.timeout(_requestTimeout);
    } catch (error) {
      if (error is BackendApiException) rethrow;
      throw BackendApiException(
          'Financial context service is unavailable: $error');
    }
  }

  Future<FinancialGoalList> fetchFinancialGoals({DateTime? asOf}) async {
    final response = await _financialGoalRequest(
      'GET',
      '/v2/financial-goals',
      query: asOf == null
          ? null
          : {'asOf': asOf.toUtc().toIso8601String().substring(0, 10)},
    );
    if (response.statusCode != 200) {
      throw BackendApiException(
          'Financial goal service returned ${response.statusCode}. Please try again.');
    }
    try {
      return FinancialGoalList.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body) as Map));
    } catch (error) {
      throw BackendApiException(
          'Financial goal response could not be read: $error');
    }
  }

  Future<FinancialGoal> createFinancialGoal(FinancialGoal goal) =>
      _financialGoalMutation(
          'POST', '/v2/financial-goals', goal.toRequestJson());

  Future<FinancialGoal> updateFinancialGoal(FinancialGoal goal) =>
      _financialGoalMutation(
          'PUT',
          '/v2/financial-goals/${Uri.encodeComponent(goal.id)}',
          goal.toRequestJson());

  Future<FinancialGoal> pauseFinancialGoal(String id) => _financialGoalMutation(
      'POST', '/v2/financial-goals/${Uri.encodeComponent(id)}/pause', const {});

  Future<FinancialGoal> resumeFinancialGoal(String id) =>
      _financialGoalMutation('POST',
          '/v2/financial-goals/${Uri.encodeComponent(id)}/resume', const {});

  Future<FinancialGoal> completeFinancialGoal(String id) =>
      _financialGoalMutation('POST',
          '/v2/financial-goals/${Uri.encodeComponent(id)}/complete', const {});

  Future<FinancialGoal> recordFinancialGoalContribution(
    String id,
    GoalContribution contribution,
    String currency,
  ) =>
      _financialGoalMutation(
        'POST',
        '/v2/financial-goals/${Uri.encodeComponent(id)}/contributions',
        contribution.toRequestJson(currency),
      );

  Future<void> deleteFinancialGoal(String id) async {
    final response = await _financialGoalRequest(
        'DELETE', '/v2/financial-goals/${Uri.encodeComponent(id)}');
    if (response.statusCode != 204) {
      throw BackendApiException(
          'Financial goal service returned ${response.statusCode}. Please try again.');
    }
  }

  Future<FinancialGoal> _financialGoalMutation(
    String method,
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _financialGoalRequest(method, path, body: body);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw BackendApiException(
          'Financial goal service returned ${response.statusCode}. Please try again.');
    }
    try {
      return FinancialGoal.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body) as Map));
    } catch (error) {
      throw BackendApiException(
          'Financial goal response could not be read: $error');
    }
  }

  Future<http.Response> _financialGoalRequest(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    try {
      final uri = Uri.parse('$_transactionCommandBaseUrl$path')
          .replace(queryParameters: query);
      final Future<http.Response> request;
      switch (method) {
        case 'GET':
          request = _client.get(uri, headers: _headers);
          break;
        case 'POST':
          request =
              _client.post(uri, headers: _headers, body: jsonEncode(body));
          break;
        case 'PUT':
          request = _client.put(uri, headers: _headers, body: jsonEncode(body));
          break;
        case 'DELETE':
          request = _client.delete(uri, headers: _headers);
          break;
        default:
          throw ArgumentError.value(method, 'method');
      }
      return await request.timeout(_requestTimeout);
    } catch (error) {
      if (error is BackendApiException) rethrow;
      throw BackendApiException(
          'Financial goal service is unavailable: $error');
    }
  }

  Future<IncomeSourceList> fetchIncomeSources() async {
    final response = await _incomeRequest('GET', '/v2/income-sources');
    if (response.statusCode != 200) {
      throw BackendApiException(
          'Income source service returned ${response.statusCode}. Please try again.');
    }
    try {
      return IncomeSourceList.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body) as Map));
    } catch (error) {
      throw BackendApiException(
          'Income source response could not be read: $error');
    }
  }

  Future<IncomeSource> createIncomeSource(IncomeSource source) =>
      _incomeMutation('POST', '/v2/income-sources', source.toRequestJson());

  Future<IncomeSource> updateIncomeEffectiveDates(
    String id,
    DateTime effectiveFrom,
    DateTime? effectiveTo,
  ) =>
      _incomeMutation(
        'PUT',
        '/v2/income-sources/${Uri.encodeComponent(id)}/effective-dates',
        {
          'effectiveFrom':
              effectiveFrom.toUtc().toIso8601String().substring(0, 10),
          if (effectiveTo != null)
            'effectiveTo':
                effectiveTo.toUtc().toIso8601String().substring(0, 10),
        },
      );

  Future<IncomeSource> confirmIncomeSuggestion(String id) => _incomeMutation(
      'POST',
      '/v2/income-sources/${Uri.encodeComponent(id)}/suggestion/confirm',
      const {});

  Future<IncomeSource> rejectIncomeSuggestion(String id) => _incomeMutation(
      'POST',
      '/v2/income-sources/${Uri.encodeComponent(id)}/suggestion/reject',
      const {});

  Future<IncomeSummary> fetchIncomeSummary({
    required DateTime periodStart,
    required DateTime periodEnd,
    required DateTime asOf,
    String currency = 'INR',
  }) async {
    final response = await _incomeRequest(
      'GET',
      '/v2/income-summary',
      query: {
        'periodStart': periodStart.toUtc().toIso8601String().substring(0, 10),
        'periodEnd': periodEnd.toUtc().toIso8601String().substring(0, 10),
        'asOf': asOf.toUtc().toIso8601String().substring(0, 10),
        'currency': currency,
      },
    );
    if (response.statusCode != 200) {
      throw BackendApiException(
          'Income summary service returned ${response.statusCode}. Please try again.');
    }
    try {
      return IncomeSummary.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body) as Map));
    } catch (error) {
      throw BackendApiException(
          'Income summary response could not be read: $error');
    }
  }

  Future<IncomeSource> _incomeMutation(
    String method,
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _incomeRequest(method, path, body: body);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw BackendApiException(
          'Income source service returned ${response.statusCode}. Please try again.');
    }
    try {
      return IncomeSource.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body) as Map));
    } catch (error) {
      throw BackendApiException(
          'Income source response could not be read: $error');
    }
  }

  Future<http.Response> _incomeRequest(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    try {
      final uri = Uri.parse('$_transactionCommandBaseUrl$path')
          .replace(queryParameters: query);
      final Future<http.Response> request;
      switch (method) {
        case 'GET':
          request = _client.get(uri, headers: _headers);
          break;
        case 'POST':
          request =
              _client.post(uri, headers: _headers, body: jsonEncode(body));
          break;
        case 'PUT':
          request = _client.put(uri, headers: _headers, body: jsonEncode(body));
          break;
        default:
          throw ArgumentError.value(method, 'method');
      }
      return await request.timeout(_requestTimeout);
    } catch (error) {
      if (error is BackendApiException) rethrow;
      throw BackendApiException('Income source service is unavailable: $error');
    }
  }

  Future<List<TransactionItem>> fetchTransactions() async {
    try {
      final transactions = <TransactionItem>[];
      final seenCursors = <String>{};
      String? cursor;
      do {
        final queryParameters = <String, String>{
          'limit': '100',
          if (cursor != null) 'cursor': cursor,
        };
        final response = await _client
            .get(
              Uri.parse('$_baseUrl/transactions')
                  .replace(queryParameters: queryParameters),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 5));
        if (response.statusCode != 200) {
          return [];
        }

        final decoded = jsonDecode(response.body);
        final List<dynamic> items;
        String? nextCursor;
        if (decoded is List<dynamic>) {
          items = decoded;
        } else if (decoded is Map<String, dynamic> &&
            decoded['items'] is List) {
          items = decoded['items'] as List<dynamic>;
          final value = decoded['nextCursor'];
          if (value != null && value is! String) {
            throw const FormatException(
                'Transaction response cursor is invalid');
          }
          nextCursor = value as String?;
        } else {
          throw const FormatException('Transaction response items are invalid');
        }
        transactions.addAll(items.map((item) =>
            TransactionItem.fromJson(Map<String, dynamic>.from(item as Map))));

        if (nextCursor == null || nextCursor.isEmpty) {
          return transactions;
        }
        if (!seenCursors.add(nextCursor)) {
          throw const FormatException('Transaction response cursor repeated');
        }
        cursor = nextCursor;
      } while (true);
    } catch (e) {
      debugPrint('BackendApiService.fetchTransactions error: $e');
    }
    return [];
  }

  Future<bool> createTransaction(TransactionItem txn) async {
    return _mutationQueue.run(() => _createDurableTransaction(txn));
  }

  Future<ReconciliationReviewQueue?> fetchReconciliationReviewQueue() async {
    try {
      final response = await _withRequestTimeout(
        _client.get(
          Uri.parse(
              '$_transactionCommandBaseUrl/v2/reconciliation/review-queue'),
          headers: _headers,
        ),
      );
      if (response == null || response.statusCode != 200) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const FormatException('Reconciliation review queue is invalid');
      }
      final pending = <TransactionItem>[];
      final canonical = <TransactionItem>[];
      for (final item in decoded) {
        if (item is! Map || item['candidate'] is! Map) {
          throw const FormatException('Reconciliation review item is invalid');
        }
        pending.add(TransactionItem.fromJson(
            Map<String, dynamic>.from(item['candidate'] as Map)));
        if (item['canonical'] != null) {
          if (item['canonical'] is! Map) {
            throw const FormatException(
                'Canonical reconciliation item is invalid');
          }
          canonical.add(TransactionItem.fromJson(
              Map<String, dynamic>.from(item['canonical'] as Map)));
        }
      }
      return ReconciliationReviewQueue(pending, canonical);
    } catch (error) {
      debugPrint(
          'BackendApiService.fetchReconciliationReviewQueue error: $error');
      return null;
    }
  }

  Future<TransactionItem?> mergeReconciledDuplicate({
    required String canonicalTransactionId,
    required String duplicateTransactionId,
  }) async {
    return _reconciliationMutation(
      method: 'POST',
      path:
          '/v2/reconciliation/${Uri.encodeComponent(duplicateTransactionId)}/merge',
      body: {'canonicalTransactionId': canonicalTransactionId},
    );
  }

  Future<TransactionItem?> confirmReconciledTransaction(
    TransactionItem transaction,
  ) async {
    final categoryId = transaction.categoryId?.trim();
    if (categoryId == null || categoryId.isEmpty) {
      return null;
    }
    return _reconciliationMutation(
      method: 'PUT',
      path: '/v2/reconciliation/${Uri.encodeComponent(transaction.id)}/confirm',
      body: {'categoryId': categoryId},
    );
  }

  Future<TransactionItem?> _reconciliationMutation({
    required String method,
    required String path,
    required Map<String, String> body,
  }) async {
    try {
      final uri = Uri.parse('$_transactionCommandBaseUrl$path');
      final response = await _withRequestTimeout(
        method == 'POST'
            ? _client.post(uri, headers: _headers, body: jsonEncode(body))
            : _client.put(uri, headers: _headers, body: jsonEncode(body)),
      );
      if (response == null || response.statusCode != 200) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('Reconciliation response is invalid');
      }
      return TransactionItem.fromJson(Map<String, dynamic>.from(decoded));
    } catch (error) {
      debugPrint('BackendApiService.reconciliationMutation error: $error');
      return null;
    }
  }

  Future<bool> batchCreateTransactions(List<TransactionItem> txns) async {
    if (txns.isEmpty) return true;
    return _mutationQueue.run(() async {
      var allSucceeded = true;
      for (final txn in txns) {
        if (!await _createDurableTransaction(txn)) {
          allSucceeded = false;
        }
      }
      return allSucceeded;
    });
  }

  /// Persists a reviewed transaction before applying its canonical category
  /// correction, which also creates the payee rule on the backend.
  Future<TransactionItem?> confirmReviewedTransaction(
    TransactionItem transaction,
  ) {
    return _mutationQueue.run(() async {
      _lastTransactionError = null;
      try {
        if (!await _createDurableTransaction(transaction)) {
          return null;
        }
        final correction = await _learnVendorRule(transaction);
        return correction == null
            ? null
            : transaction.copyWith(
                categoryId: correction.categoryId,
                subCategory: correction.subCategory,
              );
      } catch (error) {
        debugPrint(
            'BackendApiService.confirmReviewedTransaction error: $error');
        return null;
      }
    });
  }

  Future<bool> clearAllCloudData() async {
    return _mutationQueue.run(() async {
      try {
        final response = await http
            .delete(Uri.parse('$_baseUrl/data'), headers: _headers)
            .timeout(const Duration(seconds: 5));
        return response.statusCode == 200;
      } catch (e) {
        debugPrint('BackendApiService.clearAllCloudData error: $e');
        return false;
      }
    });
  }

  Future<_VendorRuleCorrection?> _learnVendorRule(
    TransactionItem transaction,
  ) async {
    final categoryId = transaction.categoryId?.trim();
    if (categoryId == null || categoryId.isEmpty) {
      return null;
    }
    final subCategory = transaction.subCategory?.trim();
    final payeeNickname = transaction.merchantName.trim();
    final body = <String, String>{
      'categoryId': categoryId,
      if (subCategory != null && subCategory.isNotEmpty)
        'subCategory': subCategory,
      if (payeeNickname.isNotEmpty) 'payeeNickname': payeeNickname,
    };

    try {
      final response = await _withRequestTimeout(
        _client.put(
          Uri.parse(
            '$_transactionCommandBaseUrl/v2/transactions/'
            '${Uri.encodeComponent(transaction.id)}/category',
          ),
          headers: _headers,
          body: jsonEncode(body),
        ),
      );
      if (response == null || response.statusCode != 200) {
        return null;
      }
      final correction = _VendorRuleCorrection.parse(response.body);
      return correction.transactionId == transaction.id ? correction : null;
    } on http.ClientException catch (error) {
      debugPrint('BackendApiService.learnVendorRule client error: $error');
      return null;
    } on FormatException catch (error) {
      debugPrint('BackendApiService.learnVendorRule invalid response: $error');
      return null;
    }
  }

  Future<bool> _createDurableTransaction(TransactionItem transaction) async {
    final preferences = await _preferences();
    final commandIds = _readDurableCommandIds(preferences);
    final commandId = commandIds[transaction.id] ?? _newCommandId(transaction);
    if (!commandIds.containsKey(transaction.id)) {
      commandIds[transaction.id] = commandId;
      if (!await preferences.setString(
        durableTransactionCommandsKey,
        jsonEncode(commandIds),
      )) {
        return false;
      }
    }

    final command = Map<String, dynamic>.from(transaction.toJson())
      ..['id'] = commandId;
    final initialStatus = await _submitCommand(command);
    if (initialStatus == null || initialStatus.id != commandId) {
      return false;
    }
    return _awaitTerminalStatus(
        preferences, commandIds, transaction.id, commandId, initialStatus);
  }

  Future<_TransactionCommandStatus?> _submitCommand(
    Map<String, dynamic> command,
  ) async {
    try {
      final response = await _withRequestTimeout(
        _client.post(
          Uri.parse('$_transactionCommandBaseUrl/v2/transactions'),
          headers: _headers,
          body: jsonEncode(command),
        ),
      );
      if (response == null || response.statusCode != 202) {
        return null;
      }
      return _TransactionCommandStatus.parse(response.body);
    } on http.ClientException catch (error) {
      debugPrint('BackendApiService.createTransaction client error: $error');
      return null;
    } on FormatException catch (error) {
      debugPrint(
          'BackendApiService.createTransaction invalid response: $error');
      return null;
    }
  }

  Future<bool> _awaitTerminalStatus(
    SharedPreferences preferences,
    Map<String, String> commandIds,
    String transactionId,
    String commandId,
    _TransactionCommandStatus status,
  ) async {
    var current = status;
    for (var poll = 0; poll < _maxStatusPolls; poll++) {
      if (current.isTerminal) {
        commandIds.remove(transactionId);
        final removed = await preferences.setString(
          durableTransactionCommandsKey,
          jsonEncode(commandIds),
        );
        if (!current.isPersisted) {
          _lastTransactionError = current.failureReason ??
              'This transaction was not saved. Rescan Gmail and confirm it before assigning a category.';
        }
        return removed && current.isPersisted;
      }
      await _wait(_statusPollInterval);
      final next = await _fetchCommandStatus(commandId);
      if (next == null || next.id != commandId) {
        return false;
      }
      current = next;
    }
    return false;
  }

  Future<_TransactionCommandStatus?> _fetchCommandStatus(
      String commandId) async {
    try {
      final response = await _withRequestTimeout(
        _client.get(
          Uri.parse(
            '$_transactionCommandBaseUrl/v2/transactions/${Uri.encodeComponent(commandId)}/status',
          ),
          headers: _headers,
        ),
      );
      if (response == null || response.statusCode != 200) {
        _lastTransactionError = response == null
            ? 'The category service did not respond. Check your connection and try again.'
            : _responseMessage(
                response,
                'The category rule could not be saved. Try again.',
              );
        return null;
      }
      return _TransactionCommandStatus.parse(response.body);
    } on http.ClientException catch (error) {
      debugPrint('BackendApiService.transactionStatus client error: $error');
      return null;
    } on FormatException catch (error) {
      debugPrint(
          'BackendApiService.transactionStatus invalid response: $error');
      return null;
    }
  }

  String _responseMessage(http.Response response, String fallback) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['message'] is String) {
        final message = (decoded['message'] as String).trim();
        if (message.isNotEmpty) return message;
      }
    } on FormatException {
      // Use the safe client-facing fallback for non-JSON API errors.
    }
    return fallback;
  }

  Map<String, String> _readDurableCommandIds(SharedPreferences preferences) {
    final serialized = preferences.getString(durableTransactionCommandsKey);
    if (serialized == null) {
      return <String, String>{};
    }
    final value = jsonDecode(serialized);
    if (value is! Map<String, dynamic>) {
      throw const FormatException(
          'Durable transaction command storage is invalid');
    }
    return Map<String, String>.fromEntries(value.entries.map((entry) {
      if (entry.value is! String ||
          !RegExp(_commandIdPattern).hasMatch(entry.value as String)) {
        throw const FormatException(
            'Durable transaction command id is invalid');
      }
      return MapEntry(entry.key, entry.value as String);
    }));
  }

  String _newCommandId(TransactionItem transaction) {
    if (RegExp(_commandIdPattern).hasMatch(transaction.id)) {
      return transaction.id;
    }
    final entropy =
        '${transaction.id}\u0000${DateTime.now().microsecondsSinceEpoch}'
        '\u0000${Random.secure().nextInt(1 << 32)}';
    return 'cmd-${sha256.convert(utf8.encode(entropy))}';
  }

  Future<http.Response?> _withRequestTimeout(Future<http.Response> request) {
    return request
        .then<http.Response?>((response) => response)
        .timeout(_requestTimeout, onTimeout: () => null);
  }
}

class _TransactionCommandStatus {
  const _TransactionCommandStatus(this.id, this.status, this.failureReason);

  final String id;
  final String status;
  final String? failureReason;

  bool get isTerminal =>
      status == 'COMPLETED' || status == 'NEEDS_REVIEW' || status == 'FAILED';

  bool get isPersisted => status == 'COMPLETED' || status == 'NEEDS_REVIEW';

  static _TransactionCommandStatus parse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic> ||
        decoded['id'] is! String ||
        decoded['status'] is! String) {
      throw const FormatException('Invalid transaction command status');
    }
    const knownStatuses = {
      'PENDING',
      'PROCESSING',
      'COMPLETED',
      'NEEDS_REVIEW',
      'FAILED',
    };
    final status = decoded['status'] as String;
    if (!knownStatuses.contains(status)) {
      throw const FormatException('Unknown transaction command status');
    }
    final failureReason = decoded['failureReason'];
    if (failureReason != null && failureReason is! String) {
      throw const FormatException('Invalid transaction command failure reason');
    }
    return _TransactionCommandStatus(
      decoded['id'] as String,
      status,
      failureReason as String?,
    );
  }
}

class _VendorRuleCorrection {
  const _VendorRuleCorrection({
    required this.transactionId,
    required this.categoryId,
    this.subCategory,
  });

  final String transactionId;
  final String categoryId;
  final String? subCategory;

  static _VendorRuleCorrection parse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic> ||
        decoded['id'] is! String ||
        decoded['id'].trim().isEmpty ||
        decoded['categoryId'] is! String ||
        decoded['categoryId'].trim().isEmpty) {
      throw const FormatException('Invalid vendor rule correction');
    }

    final subCategory = decoded['subCategory'];
    if (subCategory != null && subCategory is! String) {
      throw const FormatException('Invalid vendor rule subcategory');
    }
    return _VendorRuleCorrection(
      transactionId: decoded['id'] as String,
      categoryId: decoded['categoryId'] as String,
      subCategory: subCategory as String?,
    );
  }
}

class AnalyticsExport {
  const AnalyticsExport({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });

  final List<int> bytes;
  final String filename;
  final String mimeType;
}

class BackendApiException implements Exception {
  const BackendApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

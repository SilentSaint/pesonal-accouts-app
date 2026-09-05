import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/recurring_commitment.dart';
import 'api_config.dart';
import 'auth_service.dart';

class RecurringCommitmentsApiService {
  RecurringCommitmentsApiService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  String get _baseUrl => ApiConfig.baseUrl.endsWith('/api')
      ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - '/api'.length)
      : ApiConfig.baseUrl;

  Map<String, String> get _headers => AuthService()
      .withBackendAuthorization({'Content-Type': 'application/json'});

  Future<RecurringCommitmentList> fetch({DateTime? asOf}) async {
    final response = await _request(
      'GET',
      '/v2/recurring-commitments',
      query: asOf == null ? null : {'asOf': _date(asOf)},
    );
    return _list(response);
  }

  Future<RecurringCommitment> create(RecurringCommitment commitment) =>
      _mutation('POST', '/v2/recurring-commitments', commitment.toRequestJson(),
          expected: 201);

  Future<RecurringCommitment> update(RecurringCommitment commitment) =>
      _mutation(
          'PUT',
          '/v2/recurring-commitments/${Uri.encodeComponent(commitment.id)}',
          commitment.toRequestJson());

  Future<RecurringCommitment> confirm(String id) => _operation(id, 'confirm');
  Future<RecurringCommitment> ignore(String id) => _operation(id, 'ignore');
  Future<RecurringCommitment> cancel(String id) => _operation(id, 'cancel');
  Future<RecurringCommitment> restore(String id) => _operation(id, 'restore');

  Future<RecurringCommitment> _operation(String id, String operation) =>
      _mutation(
          'POST',
          '/v2/recurring-commitments/${Uri.encodeComponent(id)}/$operation',
          const {});

  Future<RecurringCommitmentList> _list(http.Response response) {
    if (response.statusCode != 200) {
      throw RecurringCommitmentsApiException(
          'Recurring commitments service returned ${response.statusCode}.');
    }
    try {
      return Future.value(RecurringCommitmentList.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body) as Map)));
    } catch (error) {
      throw RecurringCommitmentsApiException(
          'Recurring commitments response could not be read: $error');
    }
  }

  Future<RecurringCommitment> _mutation(
    String method,
    String path,
    Map<String, dynamic> body, {
    int expected = 200,
  }) async {
    final response = await _request(method, path, body: body);
    if (response.statusCode != expected) {
      throw RecurringCommitmentsApiException(
          'Recurring commitments service returned ${response.statusCode}.');
    }
    try {
      return RecurringCommitment.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body) as Map));
    } catch (error) {
      throw RecurringCommitmentsApiException(
          'Recurring commitment response could not be read: $error');
    }
  }

  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
      final request = switch (method) {
        'GET' => _client.get(uri, headers: _headers),
        'POST' => _client.post(uri, headers: _headers, body: jsonEncode(body)),
        'PUT' => _client.put(uri, headers: _headers, body: jsonEncode(body)),
        _ => throw ArgumentError.value(method, 'method'),
      };
      return await request.timeout(const Duration(seconds: 5));
    } catch (error) {
      if (error is RecurringCommitmentsApiException) rethrow;
      throw RecurringCommitmentsApiException(
          'Recurring commitments service is unavailable: $error');
    }
  }
}

class RecurringCommitmentsApiException implements Exception {
  const RecurringCommitmentsApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

String _date(DateTime value) => DateTime.utc(value.year, value.month, value.day)
    .toIso8601String()
    .substring(0, 10);

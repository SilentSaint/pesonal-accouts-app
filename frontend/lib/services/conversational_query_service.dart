import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/conversational_finance_query.dart';
import 'api_config.dart';
import 'auth_service.dart';

class ConversationalQueryException implements Exception {
  const ConversationalQueryException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ConversationalQueryService {
  ConversationalQueryService({
    http.Client? client,
    String? baseUrl,
    Duration timeout = const Duration(seconds: 5),
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConfig.baseUrl,
        _timeout = timeout;

  final http.Client _client;
  final String _baseUrl;
  final Duration _timeout;

  String get _queryBaseUrl => _baseUrl.endsWith('/api')
      ? _baseUrl.substring(0, _baseUrl.length - '/api'.length)
      : _baseUrl;

  Future<ConversationalFinanceQueryResponse> ask(String question) async {
    if (question.trim().isEmpty) {
      throw ArgumentError.value(question, 'question', 'cannot be blank');
    }
    final auth = AuthService();
    final headers = auth.withBackendAuthorization({
      'Content-Type': 'application/json',
      if (auth.idToken != null) 'Authorization': '******',
    });
    try {
      final response = await _client
          .post(
            Uri.parse('$_queryBaseUrl/v2/finance-queries'),
            headers: headers,
            body: jsonEncode({'question': question.trim()}),
          )
          .timeout(_timeout);
      if (response.statusCode != 200) {
        throw ConversationalQueryException(
            'The conversational query service returned ${response.statusCode}.');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('Conversational query response is invalid');
      }
      return ConversationalFinanceQueryResponse.fromJson(
          Map<String, dynamic>.from(decoded));
    } on ConversationalQueryException {
      rethrow;
    } on FormatException catch (error) {
      throw ConversationalQueryException(
          'The conversational query response could not be read: $error');
    } catch (error) {
      throw ConversationalQueryException(
          'The conversational query service is unavailable: $error');
    }
  }
}

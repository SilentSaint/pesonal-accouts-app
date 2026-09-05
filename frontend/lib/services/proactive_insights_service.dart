import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/proactive_insight.dart';
import 'api_config.dart';
import 'auth_service.dart';

class ProactiveInsightsService {
  ProactiveInsightsService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  String get _baseUrl => ApiConfig.baseUrl.endsWith('/api')
      ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 4)
      : ApiConfig.baseUrl;

  Map<String, String> get _headers => AuthService()
      .withBackendAuthorization({'Content-Type': 'application/json'});

  Future<List<ProactiveInsight>> load({bool includeDismissed = false}) async {
    final response = await _client
        .get(
          Uri.parse('$_baseUrl/v2/insights').replace(
            queryParameters:
                includeDismissed ? {'includeDismissed': 'true'} : null,
          ),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) {
      throw StateError('The insight service returned ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['items'] is! List) {
      throw const FormatException('Insight response is invalid');
    }
    return (decoded['items'] as List)
        .map(ProactiveInsight.fromJson)
        .toList(growable: false);
  }

  Future<void> dismiss(String insightId) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/v2/insights/$insightId/dismiss'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 204) {
      throw StateError('The insight service returned ${response.statusCode}.');
    }
  }
}

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'auth_service.dart';

class GmailScanResult {
  final int emailsScanned;
  final List<Map<String, dynamic>> transactionCandidates;
  final List<Map<String, dynamic>> balanceSnapshots;
  final List<Map<String, dynamic>> rawScannedEmails;
  final String message;
  final String? queryUsed;
  final String? error;
  final bool success;
  final bool requiresReconnect;
  final String? extractionMode;
  final String? fallbackReason;
  final String? correlationId;
  final String? failureStage;

  const GmailScanResult({
    required this.emailsScanned,
    required this.transactionCandidates,
    this.balanceSnapshots = const [],
    this.rawScannedEmails = const [],
    required this.message,
    this.queryUsed,
    this.error,
    this.success = true,
    this.requiresReconnect = false,
    this.extractionMode,
    this.fallbackReason,
    this.correlationId,
    this.failureStage,
  });

  factory GmailScanResult.fromJson(Map<String, dynamic> json) =>
      GmailScanResult(
        emailsScanned: (json['emailsScanned'] as num?)?.toInt() ?? 0,
        transactionCandidates:
            (json['transactionCandidates'] as List<dynamic>?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ??
            [],
        balanceSnapshots:
            (json['balanceSnapshots'] as List<dynamic>?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ??
            [],
        rawScannedEmails:
            (json['rawScannedEmails'] as List<dynamic>?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ??
            [],
        message: json['message'] as String? ?? '',
        queryUsed: json['queryUsed'] as String?,
        error: json['error'] as String?,
        success: json['error'] == null,
        extractionMode: json['extractionMode'] as String?,
        fallbackReason: json['fallbackReason'] as String?,
        correlationId: json['correlationId'] as String?,
        failureStage: json['failureStage'] as String?,
      );

  factory GmailScanResult.failure(
    String error, {
    bool requiresReconnect = false,
  }) => GmailScanResult(
    emailsScanned: 0,
    transactionCandidates: [],
    balanceSnapshots: const [],
    rawScannedEmails: const [],
    message: error,
    error: error,
    success: false,
    requiresReconnect: requiresReconnect,
  );
}

class GmailScanService {
  static final GmailScanService _instance = GmailScanService._internal();
  factory GmailScanService() => _instance;
  GmailScanService._internal({http.Client? client, AuthService? authService})
    : _client = client ?? http.Client(),
      _authService = authService;

  factory GmailScanService.forTesting({
    required http.Client client,
    required AuthService authService,
  }) => GmailScanService._internal(client: client, authService: authService);

  final http.Client _client;
  final AuthService? _authService;

  Future<GmailScanResult> scanInbox({
    String? query,
    int? afterTimestamp,
    int? beforeTimestamp,
    int? maxResults,
  }) async {
    final auth = _authService ?? AuthService();
    final gmailToken = await auth.ensureFreshGmailToken();
    if (gmailToken == null) {
      return GmailScanResult.failure(
        auth.lastError ??
            'Gmail authorization required. Please grant gmail.readonly permission to scan your inbox.',
      );
    }

    try {
      final body = jsonEncode({
        if (query != null && query.isNotEmpty) 'query': query,
        if (afterTimestamp != null) 'afterTimestamp': afterTimestamp,
        if (beforeTimestamp != null) 'beforeTimestamp': beforeTimestamp,
        if (maxResults != null) 'maxResults': maxResults,
      });

      final headers = auth.withBackendAuthorization({
        'Content-Type': 'application/json',
        if (auth.idToken != null) 'Authorization': 'Bearer ${auth.idToken}',
        'X-Gmail-Token': gmailToken,
      });

      final response = await _client
          .post(
            Uri.parse('${ApiConfig.baseUrl}/gmail/scan'),
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint(
          '[GMAIL_SCAN] response received: extractionMode=${json['extractionMode']}, emailsScanned=${json['emailsScanned']}, fallbackReason=${json['fallbackReason']}',
        );
        return GmailScanResult.fromJson(json);
      } else {
        String errMsg = 'HTTP ${response.statusCode}';
        try {
          final errJson = jsonDecode(response.body);
          errMsg = errJson['error'] ?? errJson['message'] ?? errMsg;
        } catch (_) {}

        debugPrint(
          '[GMAIL_SCAN] request failed: status=${response.statusCode}, failureStage=${errMsg.contains('Gmail') ? 'gmail_or_backend' : 'unknown'}',
        );

        final lowerError = errMsg.toLowerCase();
        final isInsufficientScope =
            response.statusCode == 403 ||
            lowerError.contains('insufficient_scope') ||
            lowerError.contains('insufficient authentication scopes');
        if (isInsufficientScope) {
          await auth.clearExpiredGmailToken();
          return GmailScanResult.failure(
            'Gmail permission has expired or is incomplete. Reconnect Gmail and try again.',
            requiresReconnect: true,
          );
        }

        final isAuthErr =
            response.statusCode == 401 ||
            errMsg.toLowerCase().contains(
              'invalid authentication credentials',
            ) ||
            lowerError.contains('invalid credentials') ||
            lowerError.contains('invalid_grant');

        if (isAuthErr) {
          debugPrint('GmailScanService: Gmail token rejected; refreshing');
          await auth.clearExpiredGmailToken();

          final freshToken = await auth.ensureFreshGmailToken();
          if (freshToken != null &&
              freshToken.isNotEmpty &&
              freshToken != gmailToken) {
            debugPrint('GmailScanService: Retrying scan with fresh token...');
            final retryHeaders = auth.withBackendAuthorization({
              'Content-Type': 'application/json',
              if (auth.idToken != null)
                'Authorization': 'Bearer ${auth.idToken}',
              'X-Gmail-Token': freshToken,
            });
            final retryResponse = await _client
                .post(
                  Uri.parse('${ApiConfig.baseUrl}/gmail/scan'),
                  headers: retryHeaders,
                  body: body,
                )
                .timeout(const Duration(seconds: 28));

            if (retryResponse.statusCode == 200) {
              final json =
                  jsonDecode(retryResponse.body) as Map<String, dynamic>;
              debugPrint(
                '[GMAIL_SCAN] retry succeeded: extractionMode=${json['extractionMode']}, emailsScanned=${json['emailsScanned']}',
              );
              return GmailScanResult.fromJson(json);
            }
            if (retryResponse.statusCode == 403) {
              await auth.clearExpiredGmailToken();
              return GmailScanResult.failure(
                'Gmail permission has expired or is incomplete. Reconnect Gmail and try again.',
                requiresReconnect: true,
              );
            }
          }
        }

        debugPrint('GmailScanService: scan failed');
        return GmailScanResult.failure(
          'Gmail could not be scanned right now. Please try again.',
        );
      }
    } catch (error) {
      debugPrint('[GMAIL_SCAN] request exception: ${error.runtimeType}');
      return GmailScanResult.failure(
        'Gmail could not be scanned right now. Please try again.',
      );
    }
  }
}

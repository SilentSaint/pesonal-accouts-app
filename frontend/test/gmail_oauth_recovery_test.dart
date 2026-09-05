import 'dart:convert';

import 'package:automatic_expense_tracker/services/auth_service.dart';
import 'package:automatic_expense_tracker/services/gmail_scan_service.dart';
import 'package:automatic_expense_tracker/ui/email_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('first Gmail grant verifies scope once and keeps OAuth tokens in memory',
      () async {
    SharedPreferences.setMockInitialValues({});
    final google = FakeGoogleOAuthClient(scopeGranted: false);
    final auth = AuthService.forTesting(googleOAuthClient: google);
    await auth.ensureInitialized();

    expect(await auth.requestGmailAccess(), isTrue);

    expect(google.requestScopesCalls, 1);
    expect(google.requestedScopes, [AuthService.gmailScope]);
    expect(auth.hasGmailAccess, isTrue);
    expect(auth.gmailAccessToken, 'gmail-access-token');
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.containsKey('auth_id_token'), isFalse);
    expect(preferences.containsKey('auth_gmail_token'), isFalse);
    expect(preferences.containsKey('auth_has_gmail'), isFalse);
  });

  test('denied Gmail consent leaves Gmail disabled without retrying consent',
      () async {
    SharedPreferences.setMockInitialValues({});
    final google = FakeGoogleOAuthClient(
      scopeGranted: false,
      consentGranted: false,
    );
    final auth = AuthService.forTesting(googleOAuthClient: google);
    await auth.ensureInitialized();

    expect(await auth.requestGmailAccess(), isFalse);

    expect(google.requestScopesCalls, 1);
    expect(auth.hasGmailAccess, isFalse);
    expect(auth.gmailAccessToken, isNull);
  });

  test(
      'an insufficient-scope response invalidates access and requires reconnect',
      () async {
    SharedPreferences.setMockInitialValues({});
    final google = FakeGoogleOAuthClient(scopeGranted: true);
    final auth = AuthService.forTesting(googleOAuthClient: google);
    await auth.ensureInitialized();
    final service = GmailScanService.forTesting(
      authService: auth,
      client: MockClient((_) async {
        google.scopeGranted = false;
        return http.Response(
          jsonEncode(
              {'error': 'Request had insufficient authentication scopes.'}),
          403,
        );
      }),
    );

    final result = await service.scanInbox();

    expect(result.success, isFalse);
    expect(result.requiresReconnect, isTrue);
    expect(result.error, contains('Reconnect Gmail'));
    expect(auth.hasGmailAccess, isFalse);
    expect(google.requestScopesCalls, 0);
  });

  testWidgets('browser consent completes before the scan request is issued',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final google = FakeGoogleOAuthClient(scopeGranted: false);
    final auth = AuthService.forTesting(googleOAuthClient: google);
    await auth.ensureInitialized();
    var scans = 0;
    final service = GmailScanService.forTesting(
      authService: auth,
      client: MockClient((_) async {
        scans++;
        return http.Response(_successfulScan(), 200);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: EmailSettingsScreen(
          authService: auth,
          gmailScanService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scan Inbox for Bank Alerts'));
    await tester.pumpAndSettle();
    expect(find.text('Gmail Permission Required'), findsOneWidget);
    expect(scans, 0);

    await tester.tap(find.text('Grant Permission'));
    await tester.pumpAndSettle();

    expect(google.requestScopesCalls, 1);
    expect(scans, 1);
    expect(find.text('Inbox Scan Results'), findsOneWidget);
  });

  testWidgets('expired Gmail scope offers Reconnect and resumes the scan',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final google = FakeGoogleOAuthClient(scopeGranted: true);
    final auth = AuthService.forTesting(googleOAuthClient: google);
    await auth.ensureInitialized();
    var scans = 0;
    final service = GmailScanService.forTesting(
      authService: auth,
      client: MockClient((_) async {
        scans++;
        if (scans == 1) {
          google.scopeGranted = false;
          return http.Response(
            jsonEncode({'error': 'Insufficient permission for Gmail scope'}),
            403,
          );
        }
        return http.Response(_successfulScan(), 200);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: EmailSettingsScreen(
          authService: auth,
          gmailScanService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan Inbox for Bank Alerts'));
    await tester.pumpAndSettle();

    expect(find.text('Reconnect Gmail'), findsOneWidget);
    await tester.tap(find.text('Reconnect Gmail'));
    await tester.pumpAndSettle();

    expect(google.requestScopesCalls, 1);
    expect(scans, 2);
    expect(find.text('Inbox Scan Results'), findsOneWidget);
  });
}

String _successfulScan() => jsonEncode({
      'emailsScanned': 1,
      'transactionCandidates': [],
      'message': 'Scan complete',
    });

class FakeGoogleOAuthClient implements GoogleOAuthClient {
  FakeGoogleOAuthClient({
    required this.scopeGranted,
    this.consentGranted = true,
  });

  bool scopeGranted;
  final bool consentGranted;
  int requestScopesCalls = 0;
  List<String> requestedScopes = const [];
  final FakeGoogleOAuthAccount _account = FakeGoogleOAuthAccount();

  @override
  GoogleOAuthAccount get currentUser => _account;

  @override
  Stream<GoogleOAuthAccount?> get onCurrentUserChanged => const Stream.empty();

  @override
  Future<bool> canAccessScopes(List<String> scopes) async => scopeGranted;

  @override
  Future<GoogleOAuthAccount> signIn() async => _account;

  @override
  Future<GoogleOAuthAccount> signInSilently() async => _account;

  @override
  Future<void> signOut() async {}

  @override
  Future<bool> requestScopes(List<String> scopes) async {
    requestScopesCalls++;
    requestedScopes = List.of(scopes);
    if (consentGranted) scopeGranted = true;
    return consentGranted;
  }
}

class FakeGoogleOAuthAccount implements GoogleOAuthAccount {
  @override
  String get displayName => 'Expense User';

  @override
  String get email => 'expense@example.test';

  @override
  String? get photoUrl => null;

  @override
  Future<GoogleOAuthCredentials> get authentication async =>
      const GoogleOAuthCredentials(
        idToken: 'identity-token',
        accessToken: 'gmail-access-token',
      );
}

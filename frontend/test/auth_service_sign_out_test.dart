import 'package:automatic_expense_tracker/services/auth_service.dart';
import 'package:automatic_expense_tracker/services/financial_data_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'sign-out removes verified Gmail authorization and local financial data',
      () async {
    SharedPreferences.setMockInitialValues({
      'auth_email': 'account@example.test',
      'auth_display_name': 'Account',
      'auth_scope_id': 'account-scope',
      'auth_id_token': 'test-id-token',
      'auth_gmail_token': 'test-gmail-token',
      'auth_has_gmail': true,
      FinancialDataCache.accountsKey: '[{"id":"account-test"}]',
    });
    final auth = AuthService.forTesting(
      googleOAuthClient: _OAuthClient(),
    );
    await auth.ensureInitialized();

    expect(auth.isAuthenticated, isTrue);
    expect(auth.hasGmailAccess, isTrue);
    expect(auth.gmailAccessToken, 'test-gmail-token');

    await auth.signOut();

    final preferences = await SharedPreferences.getInstance();
    expect(auth.isAuthenticated, isFalse);
    expect(auth.hasGmailAccess, isFalse);
    expect(auth.gmailAccessToken, isNull);
    expect(preferences.containsKey('auth_email'), isFalse);
    expect(
      preferences.containsKey(FinancialDataCache.accountsKey),
      isFalse,
    );
  });

  test('stored legacy tokens do not grant Gmail access', () async {
    SharedPreferences.setMockInitialValues({
      'auth_email': 'account@example.test',
      'auth_display_name': 'Account',
      'auth_scope_id': 'account-scope',
      'auth_id_token': 'test-id-token',
      'auth_gmail_token': 'test-gmail-token',
      'auth_has_gmail': true,
    });
    final auth = AuthService.forTesting(
      googleOAuthClient: _NoopOAuthClient(),
    );
    await auth.ensureInitialized();

    expect(auth.isAuthenticated, isTrue);
    expect(auth.hasGmailAccess, isFalse);
    expect(auth.gmailAccessToken, isNull);
  });
}

class _NoopOAuthClient implements GoogleOAuthClient {
  final _NoopOAuthAccount _account = _NoopOAuthAccount();

  @override
  GoogleOAuthAccount? get currentUser => _account;

  @override
  Stream<GoogleOAuthAccount?> get onCurrentUserChanged => const Stream.empty();

  @override
  Future<GoogleOAuthAccount?> signIn() async => _account;

  @override
  Future<GoogleOAuthAccount?> signInSilently() async => _account;

  @override
  Future<bool> canAccessScopes(List<String> scopes) async => false;

  @override
  Future<bool> requestScopes(List<String> scopes) async => false;

  @override
  Future<void> signOut() async {}
}

class _NoopOAuthAccount implements GoogleOAuthAccount {
  @override
  String get email => 'account@example.test';

  @override
  String get displayName => 'Account';

  @override
  String? get photoUrl => null;

  @override
  Future<GoogleOAuthCredentials> get authentication async =>
      const GoogleOAuthCredentials(idToken: 'verified-test-id-token');
}

class _OAuthClient implements GoogleOAuthClient {
  final _OAuthAccount _account = _OAuthAccount();

  @override
  GoogleOAuthAccount get currentUser => _account;

  @override
  Stream<GoogleOAuthAccount?> get onCurrentUserChanged => const Stream.empty();

  @override
  Future<bool> canAccessScopes(List<String> scopes) async => true;

  @override
  Future<bool> requestScopes(List<String> scopes) async => true;

  @override
  Future<GoogleOAuthAccount> signIn() async => _account;

  @override
  Future<GoogleOAuthAccount> signInSilently() async => _account;

  @override
  Future<void> signOut() async {}
}

class _OAuthAccount implements GoogleOAuthAccount {
  @override
  String get displayName => 'Account';

  @override
  String get email => 'account@example.test';

  @override
  String? get photoUrl => null;

  @override
  Future<GoogleOAuthCredentials> get authentication async =>
      const GoogleOAuthCredentials(
        idToken: 'test-id-token',
        accessToken: 'test-gmail-token',
      );
}

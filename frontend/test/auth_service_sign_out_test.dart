import 'package:automatic_expense_tracker/services/auth_service.dart';
import 'package:automatic_expense_tracker/services/financial_data_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'sign-out removes in-memory Gmail authorization and local financial data',
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
      googleOAuthClient: _NoopOAuthClient(),
    );
    await auth.ensureInitialized();

    expect(auth.isAuthenticated, isTrue);
    // A stored legacy token must not be treated as a verified Gmail grant.
    expect(auth.hasGmailAccess, isFalse);
    expect(auth.gmailAccessToken, isNull);

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
}

class _NoopOAuthClient implements GoogleOAuthClient {
  final _TestOAuthAccount _account = _TestOAuthAccount();

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

class _TestOAuthAccount implements GoogleOAuthAccount {
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

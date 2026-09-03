import 'package:automatic_expense_tracker/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'adds the active short-lived identity JWT to outgoing backend requests',
    () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService.forTesting(googleOAuthClient: _OAuthClient());
      await auth.ensureInitialized();

      final headers = auth.withBackendAuthorization({
        'Content-Type': 'application/json',
      });

      expect(headers['Authorization'], 'Bearer test-short-lived-jwt');
      expect(headers['Authorization'], isNot(contains('******')));
    },
  );

  test(
    'does not authenticate or authorize backend requests with an OAuth access token',
    () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService.forTesting(
        googleOAuthClient: _OAuthClient(
          credentials: const GoogleOAuthCredentials(
            accessToken: 'oauth-access-token',
          ),
        ),
      );
      await auth.ensureInitialized();

      expect(auth.isAuthenticated, isFalse);
      expect(auth.backendAuthorizationToken, isNull);
      expect(
        auth.withBackendAuthorization({'Content-Type': 'application/json'}),
        isNot(contains('Authorization')),
      );
    },
  );

  test(
    'keeps a verified identity signed in when optional Gmail scope check fails',
    () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService.forTesting(
        googleOAuthClient: _OAuthClient(throwOnScopeCheck: true),
      );

      await auth.ensureInitialized();

      expect(auth.isAuthenticated, isTrue);
      expect(auth.lastError, isNull);
      expect(auth.hasGmailAccess, isFalse);
    },
  );

  test(
    'restores the stored identity after a browser refresh via silent sign-in',
    () async {
      SharedPreferences.setMockInitialValues({
        'auth_email': 'test@example.test',
        'auth_display_name': 'Stored User',
        'auth_scope_id': 'stored-scope-id',
      });
      final auth = AuthService.forTesting(googleOAuthClient: _OAuthClient());

      await auth.ensureInitialized();

      expect(auth.isInitialized, isTrue);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.currentUser?.email, 'test@example.test');
    },
  );
}

class _OAuthClient implements GoogleOAuthClient {
  _OAuthClient({
    GoogleOAuthCredentials credentials = const GoogleOAuthCredentials(
      idToken: 'test-short-lived-jwt',
    ),
    this.throwOnScopeCheck = false,
  }) : _account = _OAuthAccount(credentials);

  final _OAuthAccount _account;
  final bool throwOnScopeCheck;

  @override
  GoogleOAuthAccount get currentUser => _account;

  @override
  Stream<GoogleOAuthAccount?> get onCurrentUserChanged => const Stream.empty();

  @override
  Future<bool> canAccessScopes(List<String> scopes) async {
    if (throwOnScopeCheck) {
      throw StateError('Google popup scope check failed');
    }
    return false;
  }

  @override
  Future<bool> requestScopes(List<String> scopes) async => false;

  @override
  Future<GoogleOAuthAccount> signIn() async => _account;

  @override
  Future<GoogleOAuthAccount> signInSilently() async => _account;

  @override
  Future<void> signOut() async {}
}

class _OAuthAccount implements GoogleOAuthAccount {
  _OAuthAccount(this._credentials);

  final GoogleOAuthCredentials _credentials;

  @override
  String get displayName => 'Test User';

  @override
  String get email => 'test@example.test';

  @override
  String? get photoUrl => null;

  @override
  Future<GoogleOAuthCredentials> get authentication async => _credentials;
}

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'authentication_session_guard.dart';
import 'financial_data_cache.dart';

/// Narrow OAuth port used to keep consent policy testable without platform UI.
abstract interface class GoogleOAuthClient {
  GoogleOAuthAccount? get currentUser;
  Stream<GoogleOAuthAccount?> get onCurrentUserChanged;
  Future<GoogleOAuthAccount?> signIn();
  Future<GoogleOAuthAccount?> signInSilently();
  Future<bool> canAccessScopes(List<String> scopes);
  Future<bool> requestScopes(List<String> scopes);
  Future<void> signOut();
}

abstract interface class GoogleOAuthAccount {
  String get email;
  String? get displayName;
  String? get photoUrl;
  Future<GoogleOAuthCredentials> get authentication;
}

class GoogleOAuthCredentials {
  const GoogleOAuthCredentials({this.idToken, this.accessToken});

  final String? idToken;
  final String? accessToken;
}

class GoogleSignInOAuthClient implements GoogleOAuthClient {
  GoogleSignInOAuthClient(this._googleSignIn);

  final GoogleSignIn _googleSignIn;

  @override
  GoogleOAuthAccount? get currentUser {
    final account = _googleSignIn.currentUser;
    return account == null ? null : GoogleSignInOAuthAccount(account);
  }

  @override
  Stream<GoogleOAuthAccount?> get onCurrentUserChanged =>
      _googleSignIn.onCurrentUserChanged.map(
        (account) => account == null ? null : GoogleSignInOAuthAccount(account),
      );

  @override
  Future<GoogleOAuthAccount?> signIn() async {
    final account = await _googleSignIn.signIn();
    return account == null ? null : GoogleSignInOAuthAccount(account);
  }

  @override
  Future<GoogleOAuthAccount?> signInSilently() async {
    final account = await _googleSignIn.signInSilently();
    return account == null ? null : GoogleSignInOAuthAccount(account);
  }

  @override
  Future<bool> canAccessScopes(List<String> scopes) =>
      _googleSignIn.canAccessScopes(scopes);

  @override
  Future<bool> requestScopes(List<String> scopes) =>
      _googleSignIn.requestScopes(scopes);

  @override
  Future<void> signOut() => _googleSignIn.signOut();
}

class GoogleSignInOAuthAccount implements GoogleOAuthAccount {
  GoogleSignInOAuthAccount(this._account);

  final GoogleSignInAccount _account;

  @override
  String get email => _account.email;

  @override
  String? get displayName => _account.displayName;

  @override
  String? get photoUrl => _account.photoUrl;

  @override
  Future<GoogleOAuthCredentials> get authentication async {
    final credentials = await _account.authentication;
    return GoogleOAuthCredentials(
      idToken: credentials.idToken,
      accessToken: credentials.accessToken,
    );
  }
}

class UserProfile {
  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;

  const UserProfile({
    required this.id,
    required this.email,
    required this.displayName,
    this.photoUrl,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'displayName': displayName,
    'photoUrl': photoUrl,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String,
    email: json['email'] as String,
    displayName: json['displayName'] as String,
    photoUrl: json['photoUrl'] as String?,
  );
}

String _deriveUserScopeId(String email) {
  final digest = sha256.convert(utf8.encode(email.toLowerCase().trim()));
  return digest.toString().substring(0, 32);
}

class AuthService extends ChangeNotifier {
  static const String gmailScope =
      'https://www.googleapis.com/auth/gmail.readonly';
  static const List<String> _scopes = ['email', 'profile'];
  static const String _clientId =
      '230057110188-uju5dg9caco861t3bmqjc3qvbtdcuck5.apps.googleusercontent.com';

  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  AuthService._internal()
    : _googleSignIn = GoogleSignInOAuthClient(
        GoogleSignIn(clientId: kIsWeb ? _clientId : null, scopes: _scopes),
      ) {
    _listenForGoogleIdentityChanges();
    _init();
  }

  AuthService.forTesting({required GoogleOAuthClient googleOAuthClient})
    : _googleSignIn = googleOAuthClient {
    _listenForGoogleIdentityChanges();
    _init();
  }

  final GoogleOAuthClient _googleSignIn;
  final AuthenticationSessionGuard _sessionGuard = AuthenticationSessionGuard();
  final Completer<void> _initCompleter = Completer<void>();

  UserProfile? _currentUser;
  String? _idToken;
  String? _gmailAccessToken;
  String? _lastError;
  bool _hasGmailAccess = false;
  bool _isLoading = false;
  bool _isSignedOut = false;
  Future<bool>? _gmailAuthorizationRequest;

  UserProfile? get currentUser => _currentUser;
  bool get isAuthenticated =>
      _currentUser != null && (_idToken?.isNotEmpty ?? false);
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;
  bool get hasGmailAccess => _hasGmailAccess;
  String? get gmailAccessToken => _gmailAccessToken;
  String? get idToken => _idToken;
  String? get backendAuthorizationToken => _idToken;
  String get userEmail => _currentUser?.email ?? '';
  String get displayName => _currentUser?.displayName ?? '';
  String? get photoUrl => _currentUser?.photoUrl;
  String get currentUserId =>
      _currentUser == null ? 'USER#guest' : 'USER#${_currentUser!.id}';

  Future<void> ensureInitialized() => _initCompleter.future;

  bool get isInitialized => _initCompleter.isCompleted;

  /// Adds a credential only to the outgoing request; callers must not log it.
  Map<String, String> withBackendAuthorization(Map<String, String> headers) {
    final token = backendAuthorizationToken;
    if (token == null || token.isEmpty) return headers;
    return {...headers, 'Authorization': 'Bearer $token'};
  }

  Future<void> _init() async {
    final generation = _sessionGuard.beginOperation();
    await _loadStoredProfile(generation);
    await _trySilentSignIn();
    if (!_initCompleter.isCompleted) _initCompleter.complete();
  }

  void _listenForGoogleIdentityChanges() {
    _googleSignIn.onCurrentUserChanged.listen((account) {
      if (account == null || _isSignedOut) return;
      final generation = _sessionGuard.beginOperation();
      unawaited(_onSignedIn(account, generation));
    });
  }

  Future<void> _loadStoredProfile(int expectedGeneration) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('auth_email');
      final name = prefs.getString('auth_display_name');
      final id = prefs.getString('auth_scope_id');
      final photoUrl = prefs.getString('auth_photo_url');
      if (!_isSignedOut &&
          _sessionGuard.isCurrent(expectedGeneration) &&
          email != null &&
          id != null) {
        _currentUser = UserProfile(
          id: id,
          email: email,
          displayName: name ?? email.split('@')[0],
          photoUrl: photoUrl,
        );
      }

      // Remove legacy plaintext OAuth data. Scope access is always verified
      // against the active Google session, never restored from browser storage.
      await prefs.remove('auth_id_token');
      await prefs.remove('auth_gmail_token');
      await prefs.remove('auth_has_gmail');
    } catch (_) {
      debugPrint('AuthService: failed to load stored profile');
    }
    if (_sessionGuard.isCurrent(expectedGeneration)) notifyListeners();
  }

  Future<void> _trySilentSignIn() async {
    if (_isSignedOut) return;
    final generation = _sessionGuard.beginOperation();
    try {
      final account = await _googleSignIn.signInSilently();
      if (account != null &&
          !_isSignedOut &&
          _sessionGuard.isCurrent(generation)) {
        await _onSignedIn(account, generation);
      }
    } catch (_) {
      debugPrint('AuthService: silent sign-in failed');
    }
  }

  Future<void> _onSignedIn(
    GoogleOAuthAccount account, [
    int? expectedGeneration,
  ]) async {
    try {
      final credentials = await account.authentication;
      if (expectedGeneration != null &&
          !_sessionGuard.isCurrent(expectedGeneration)) {
        return;
      }
      final scopeId = _deriveUserScopeId(account.email);
      _currentUser = UserProfile(
        id: scopeId,
        email: account.email,
        displayName: account.displayName ?? account.email.split('@')[0],
        photoUrl: account.photoUrl,
      );
      _idToken = credentials.idToken;

      // Gmail consent is optional and its web provider call must not hold the
      // primary identity unlock screen indefinitely.
      bool hasScope;
      try {
        hasScope = await _googleSignIn
            .canAccessScopes([gmailScope])
            .timeout(const Duration(seconds: 3), onTimeout: () => false);
      } catch (error) {
        // Gmail access is optional and browser popup compatibility must not
        // invalidate an otherwise verified primary identity.
        debugPrint('AuthService: Gmail scope check failed: $error');
        hasScope = false;
      }
      if (expectedGeneration != null &&
          !_sessionGuard.isCurrent(expectedGeneration)) {
        return;
      }
      _hasGmailAccess =
          hasScope && (credentials.accessToken?.isNotEmpty ?? false);
      _gmailAccessToken = _hasGmailAccess ? credentials.accessToken : null;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_email', account.email);
      await prefs.setString('auth_display_name', _currentUser!.displayName);
      await prefs.setString('auth_scope_id', scopeId);
      if (account.photoUrl != null) {
        await prefs.setString('auth_photo_url', account.photoUrl!);
      }
    } catch (_) {
      _lastError = 'Google sign-in could not be completed. Please try again.';
      debugPrint('AuthService: unable to update Google sign-in state');
    }
    notifyListeners();
  }

  /// Starts identity sign-in only after an explicit action.
  Future<bool> signInWithGoogle() async {
    _isSignedOut = false;
    final generation = _sessionGuard.beginOperation();
    _isLoading = true;
    _lastError = null;
    notifyListeners();
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        _lastError = 'Google sign-in was cancelled.';
        return false;
      }
      if (!_sessionGuard.isCurrent(generation)) return false;
      await _onSignedIn(account, generation);
      return isAuthenticated;
    } catch (_) {
      _lastError = 'Google sign-in could not be completed. Please try again.';
      debugPrint('AuthService: sign-in error');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Returns a live Gmail token only after verifying `gmail.readonly`.
  ///
  /// Consent is requested only when [allowInteractiveAuthorization] is true.
  Future<String?> ensureFreshGmailToken({
    bool allowInteractiveAuthorization = false,
  }) async {
    final generation = _sessionGuard.beginOperation();
    final expectedUserId = _currentUser?.id;
    if (expectedUserId == null) return null;
    bool isCurrentSession() =>
        _sessionGuard.isCurrent(generation) &&
        _currentUser?.id == expectedUserId;

    try {
      var account = _googleSignIn.currentUser;
      if (account == null) {
        account = await _googleSignIn.signInSilently();
        if (account == null || !isCurrentSession()) {
          await _clearGmailAccess(persistLegacyCleanup: false);
          return null;
        }
      }

      var hasScope = await _googleSignIn
          .canAccessScopes([gmailScope])
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!isCurrentSession()) return null;
      if (!hasScope && allowInteractiveAuthorization) {
        final granted = await _googleSignIn.requestScopes([gmailScope]);
        if (!granted || !isCurrentSession()) {
          await _clearGmailAccess(persistLegacyCleanup: false);
          return null;
        }
        hasScope = await _googleSignIn
            .canAccessScopes([gmailScope])
            .timeout(const Duration(seconds: 5), onTimeout: () => false);
      }
      if (!hasScope || !isCurrentSession()) {
        await _clearGmailAccess(persistLegacyCleanup: false);
        return null;
      }

      final credentials = await account.authentication;
      if (!isCurrentSession() ||
          credentials.accessToken == null ||
          credentials.accessToken!.isEmpty) {
        await _clearGmailAccess(persistLegacyCleanup: false);
        return null;
      }
      _idToken = credentials.idToken ?? _idToken;
      _gmailAccessToken = credentials.accessToken;
      _hasGmailAccess = true;
      _lastError = null;
      notifyListeners();
      return _gmailAccessToken;
    } catch (_) {
      if (isCurrentSession()) {
        _lastError =
            'Gmail authorization could not be verified. Please reconnect Gmail.';
        await _clearGmailAccess(persistLegacyCleanup: false);
      }
      debugPrint('AuthService: Gmail authorization refresh failed');
      return null;
    }
  }

  /// Requests incremental Gmail consent once for each explicit user action.
  Future<bool> requestGmailAccess() {
    final currentRequest = _gmailAuthorizationRequest;
    if (currentRequest != null) return currentRequest;
    final request = _requestGmailAccess();
    _gmailAuthorizationRequest = request;
    request.whenComplete(() {
      if (identical(_gmailAuthorizationRequest, request)) {
        _gmailAuthorizationRequest = null;
      }
    });
    return request;
  }

  Future<bool> _requestGmailAccess() async {
    if (_googleSignIn.currentUser == null && !await signInWithGoogle()) {
      return false;
    }
    final token = await ensureFreshGmailToken(
      allowInteractiveAuthorization: true,
    );
    return token != null;
  }

  /// Invalidates local state after a rejected or insufficient-scope scan.
  Future<void> clearExpiredGmailToken() =>
      _clearGmailAccess(persistLegacyCleanup: true);

  Future<void> _clearGmailAccess({required bool persistLegacyCleanup}) async {
    _gmailAccessToken = null;
    _hasGmailAccess = false;
    if (persistLegacyCleanup) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('auth_gmail_token');
        await prefs.remove('auth_has_gmail');
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    _sessionGuard.invalidate();
    _isSignedOut = true;
    _currentUser = null;
    _idToken = null;
    _gmailAccessToken = null;
    _hasGmailAccess = false;
    _isLoading = false;
    _lastError = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await FinancialDataCache(prefs).clear();
    for (final key in [
      'auth_email',
      'auth_display_name',
      'auth_scope_id',
      'auth_photo_url',
      'auth_id_token',
      'auth_gmail_token',
      'auth_has_gmail',
    ]) {
      await prefs.remove(key);
    }
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      debugPrint('AuthService: sign-out failed');
    }
  }
}

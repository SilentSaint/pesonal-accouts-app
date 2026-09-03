import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ProtectionPlatform { mobile, web }

enum BiometricAuthenticationResult { success, unavailable, failed }

abstract interface class DeviceProtectionStore {
  Future<String?> readPinCredential();
  Future<void> writePinCredential(String credential);
  Future<bool?> readLocked();
  Future<void> writeLocked(bool locked);
  Future<int?> readIdleTimeoutMinutes();
  Future<void> writeIdleTimeoutMinutes(int minutes);
  Future<bool?> readBiometricsEnabled();
  Future<void> writeBiometricsEnabled(bool enabled);
}

class SecureDeviceProtectionStore implements DeviceProtectionStore {
  SecureDeviceProtectionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _pinCredentialKey = 'device_protection.pin_credential';
  static const _lockedKey = 'device_protection.locked';
  static const _idleTimeoutKey = 'device_protection.idle_timeout_minutes';
  static const _biometricsEnabledKey = 'device_protection.biometrics_enabled';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readPinCredential() => _storage.read(key: _pinCredentialKey);

  @override
  Future<void> writePinCredential(String credential) =>
      _storage.write(key: _pinCredentialKey, value: credential);

  @override
  Future<bool?> readLocked() async {
    final value = await _storage.read(key: _lockedKey);
    return value == null ? null : value == 'true';
  }

  @override
  Future<void> writeLocked(bool locked) =>
      _storage.write(key: _lockedKey, value: locked.toString());

  @override
  Future<int?> readIdleTimeoutMinutes() async {
    final value = await _storage.read(key: _idleTimeoutKey);
    return value == null ? null : int.tryParse(value);
  }

  @override
  Future<void> writeIdleTimeoutMinutes(int minutes) =>
      _storage.write(key: _idleTimeoutKey, value: minutes.toString());

  @override
  Future<bool?> readBiometricsEnabled() async {
    final value = await _storage.read(key: _biometricsEnabledKey);
    return value == null ? null : value == 'true';
  }

  @override
  Future<void> writeBiometricsEnabled(bool enabled) =>
      _storage.write(key: _biometricsEnabledKey, value: enabled.toString());
}

class WebDeviceProtectionStore implements DeviceProtectionStore {
  static const _lockedKey = 'device_protection.locked';
  static const _idleTimeoutKey = 'device_protection.idle_timeout_minutes';

  Future<SharedPreferences> get _preferences => SharedPreferences.getInstance();

  @override
  Future<String?> readPinCredential() async => null;

  @override
  Future<void> writePinCredential(String credential) async {}

  @override
  Future<bool?> readLocked() async => (await _preferences).getBool(_lockedKey);

  @override
  Future<void> writeLocked(bool locked) async =>
      (await _preferences).setBool(_lockedKey, locked);

  @override
  Future<int?> readIdleTimeoutMinutes() async =>
      (await _preferences).getInt(_idleTimeoutKey);

  @override
  Future<void> writeIdleTimeoutMinutes(int minutes) async =>
      (await _preferences).setInt(_idleTimeoutKey, minutes);

  @override
  Future<bool?> readBiometricsEnabled() async => false;

  @override
  Future<void> writeBiometricsEnabled(bool enabled) async {}
}

abstract interface class BiometricAuthenticator {
  Future<bool> isAvailable();
  Future<bool> authenticate();
}

class LocalAuthBiometricAuthenticator implements BiometricAuthenticator {
  LocalAuthBiometricAuthenticator({LocalAuthentication? localAuthentication})
    : _localAuthentication = localAuthentication ?? LocalAuthentication();

  final LocalAuthentication _localAuthentication;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _localAuthentication.isDeviceSupported() &&
          await _localAuthentication.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate() async {
    if (!await isAvailable()) return false;
    try {
      return await _localAuthentication.authenticate(
        localizedReason: 'Confirm your identity to unlock Expense Tracker',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}

/// Coordinates secure credential verification and the app's visible lock state.
///
/// Platform operations are ports so lock behavior is testable without device APIs.
class SecurityState extends ChangeNotifier {
  static const int defaultWebIdleTimeoutMinutes = 30;

  SecurityState._(
    this._store,
    this._biometrics, {
    required ProtectionPlatform platform,
    Duration Function(int minutes)? timeoutDuration,
  }) : _platform = platform,
       _timeoutDuration =
           timeoutDuration ?? ((minutes) => Duration(minutes: minutes));

  static final SecurityState _instance = SecurityState._(
    kIsWeb ? WebDeviceProtectionStore() : SecureDeviceProtectionStore(),
    LocalAuthBiometricAuthenticator(),
    platform: kIsWeb ? ProtectionPlatform.web : ProtectionPlatform.mobile,
  );

  factory SecurityState() => _instance;

  factory SecurityState.forTesting({
    required DeviceProtectionStore store,
    required BiometricAuthenticator biometrics,
    required ProtectionPlatform platform,
    Duration Function(int minutes)? timeoutDuration,
  }) => SecurityState._(
    store,
    biometrics,
    platform: platform,
    timeoutDuration: timeoutDuration,
  );

  final DeviceProtectionStore _store;
  final BiometricAuthenticator _biometrics;
  final ProtectionPlatform _platform;
  final Duration Function(int minutes) _timeoutDuration;

  bool _isInitialized = false;
  bool _isLocked = false;
  bool _hasPin = false;
  bool _isBiometricEnabled = true;
  int _idleTimeoutMinutes = 5;
  Timer? _idleTimer;

  bool get isInitialized => _isInitialized;
  bool get isLocked => _isLocked;
  bool get hasPin => _hasPin;
  bool get isBiometricEnabled => _isBiometricEnabled;
  int get idleTimeoutMinutes => _idleTimeoutMinutes;
  ProtectionPlatform get platform => _platform;

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final pinCredential = await _store.readPinCredential();
      final persistedLocked = await _store.readLocked();
      final persistedTimeout = await _store.readIdleTimeoutMinutes();
      final persistedBiometrics = await _store.readBiometricsEnabled();

      _hasPin = pinCredential != null;
      _idleTimeoutMinutes = persistedTimeout != null && persistedTimeout > 0
          ? persistedTimeout
          : (_platform == ProtectionPlatform.web
                ? defaultWebIdleTimeoutMinutes
                : 5);
      _isBiometricEnabled = persistedBiometrics ?? true;
      // A mobile app always starts protected. A browser only restores a lock
      // created by idle timeout, so a refresh cannot reveal already-locked data.
      _isLocked =
          _platform == ProtectionPlatform.mobile || persistedLocked == true;
    } catch (_) {
      // Storage failures must never reveal financial data.
      _isLocked = true;
    }
    _isInitialized = true;
    if (!_isLocked) _startIdleTimer();
    notifyListeners();
  }

  void userActivityDetected() {
    if (_isInitialized && !_isLocked) _startIdleTimer();
  }

  Future<void> lockApp() async {
    if (!_isInitialized) await initialize();
    _idleTimer?.cancel();
    _idleTimer = null;
    _isLocked = true;
    notifyListeners();
    try {
      await _store.writeLocked(true);
    } catch (_) {
      // The in-memory lock remains active if durable storage is unavailable.
    }
  }

  void onAppLifecycleChanged(AppLifecycleState state) {
    if (_platform == ProtectionPlatform.mobile &&
        (state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached)) {
      unawaited(lockApp());
    }
  }

  Future<bool> setCustomPin(String pin) async {
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) return false;
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final hash = _hashPin(pin, salt);
    final credential = jsonEncode({
      'salt': base64UrlEncode(salt),
      'hash': base64UrlEncode(hash),
    });
    try {
      await _store.writePinCredential(credential);
      _hasPin = true;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> unlockWithPin(String pin) async {
    if (!_isInitialized || !RegExp(r'^\d{4}$').hasMatch(pin)) return false;
    try {
      final storedCredential = await _store.readPinCredential();
      if (storedCredential == null || !_matchesPin(pin, storedCredential)) {
        return false;
      }
      await _unlock();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isBiometricsAvailable() async =>
      _isBiometricEnabled && await _biometrics.isAvailable();

  Future<BiometricAuthenticationResult> unlockWithBiometrics() async {
    if (!_isInitialized || !_isBiometricEnabled) {
      return BiometricAuthenticationResult.unavailable;
    }
    if (!await _biometrics.isAvailable()) {
      return BiometricAuthenticationResult.unavailable;
    }
    if (!await _biometrics.authenticate()) {
      return BiometricAuthenticationResult.failed;
    }
    await _unlock();
    return BiometricAuthenticationResult.success;
  }

  /// Completes an explicit browser identity-provider prompt before revealing data.
  Future<bool> unlockWebSession(Future<bool> Function() reauthenticate) async {
    if (_platform != ProtectionPlatform.web || !_isInitialized) return false;
    if (!await reauthenticate()) return false;
    await _unlock();
    return true;
  }

  Future<void> toggleBiometrics(bool enabled) async {
    _isBiometricEnabled = enabled;
    try {
      await _store.writeBiometricsEnabled(enabled);
    } catch (_) {}
    notifyListeners();
  }

  Future<bool> setIdleTimeout(int minutes) async {
    if (minutes <= 0) return false;
    _idleTimeoutMinutes = minutes;
    try {
      await _store.writeIdleTimeoutMinutes(minutes);
    } catch (_) {
      return false;
    }
    if (!_isLocked) _startIdleTimer();
    notifyListeners();
    return true;
  }

  void cancelIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  Future<void> _unlock() async {
    await _store.writeLocked(false);
    _isLocked = false;
    _startIdleTimer();
    notifyListeners();
  }

  void _startIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_timeoutDuration(_idleTimeoutMinutes), () {
      unawaited(lockApp());
    });
  }

  static List<int> _hashPin(String pin, List<int> salt) =>
      sha256.convert([...salt, ...utf8.encode(pin)]).bytes;

  static bool _matchesPin(String pin, String credential) {
    final decoded = jsonDecode(credential);
    if (decoded is! Map<String, dynamic>) return false;
    final saltEncoded = decoded['salt'];
    final hashEncoded = decoded['hash'];
    if (saltEncoded is! String || hashEncoded is! String) return false;
    final expected = base64Url.decode(hashEncoded);
    final actual = _hashPin(pin, base64Url.decode(saltEncoded));
    return _constantTimeEquals(actual, expected);
  }

  static bool _constantTimeEquals(List<int> actual, List<int> expected) {
    if (actual.length != expected.length) return false;
    var difference = 0;
    for (var index = 0; index < actual.length; index++) {
      difference |= actual[index] ^ expected[index];
    }
    return difference == 0;
  }
}

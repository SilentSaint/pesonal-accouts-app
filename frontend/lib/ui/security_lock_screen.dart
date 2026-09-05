import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/security_service.dart';
import 'google_sign_in_button.dart';

class SecurityLockScreen extends StatefulWidget {
  const SecurityLockScreen({
    super.key,
    required this.onUnlocked,
    this.securityState,
    this.onWebReauthenticate,
  });

  final VoidCallback onUnlocked;
  final SecurityState? securityState;
  final Future<bool> Function()? onWebReauthenticate;

  @override
  State<SecurityLockScreen> createState() => _SecurityLockScreenState();
}

class _SecurityLockScreenState extends State<SecurityLockScreen> {
  late final SecurityState _securityState;
  String _enteredPin = '';
  String? _pinToConfirm;
  String _errorMessage = '';
  bool _isBusy = false;
  AuthService? _webAuthService;

  bool get _isWeb => _securityState.platform == ProtectionPlatform.web;
  bool get _isPinSetup => !_isWeb && !_securityState.hasPin;
  String get _heading => _isWeb
      ? 'Session locked'
      : (_isPinSetup ? 'Create security PIN' : 'Expense Tracker Locked');
  String get _description {
    if (_isWeb) {
      return 'Your session timed out. Sign in again to view your financial data.';
    }
    if (_isPinSetup) {
      return _pinToConfirm == null
          ? 'Choose a 4-digit PIN for this device.'
          : 'Enter the PIN once more to confirm it.';
    }
    return 'Enter your 4-digit security PIN or use biometrics to continue.';
  }

  @override
  void initState() {
    super.initState();
    _securityState = widget.securityState ?? SecurityState();
    if (_securityState.platform == ProtectionPlatform.web) {
      _webAuthService = AuthService()..addListener(_onWebIdentityChanged);
    }
    _initialize();
  }

  @override
  void dispose() {
    _webAuthService?.removeListener(_onWebIdentityChanged);
    super.dispose();
  }

  void _onWebIdentityChanged() {
    if (!_isWeb || _isBusy || !(_webAuthService?.isAuthenticated ?? false)) {
      return;
    }
    _completeWebIdentityUnlock();
  }

  Future<void> _completeWebIdentityUnlock() async {
    setState(() => _isBusy = true);
    final unlocked =
        await _securityState.unlockWebSession(() async => true);
    if (!mounted) return;
    setState(() => _isBusy = false);
    if (unlocked) widget.onUnlocked();
  }

  Future<void> _initialize() async {
    await _securityState.initialize();
    if (mounted) setState(() {});
  }

  void _onKeyPress(String digit) {
    if (_isBusy || _enteredPin.length == 4) return;
    setState(() {
      _enteredPin += digit;
      _errorMessage = '';
    });
    if (_enteredPin.length == 4) _submitPin();
  }

  void _onBackspace() {
    if (_isBusy || _enteredPin.isEmpty) return;
    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      _errorMessage = '';
    });
  }

  Future<void> _submitPin() async {
    if (_isPinSetup) {
      if (_pinToConfirm == null) {
        setState(() {
          _pinToConfirm = _enteredPin;
          _enteredPin = '';
        });
        return;
      }
      if (_enteredPin != _pinToConfirm) {
        setState(() {
          _enteredPin = '';
          _pinToConfirm = null;
          _errorMessage = 'PINs did not match. Choose your PIN again.';
        });
        return;
      }
      setState(() => _isBusy = true);
      final saved = await _securityState.setCustomPin(_enteredPin);
      if (!mounted) return;
      setState(() => _isBusy = false);
      if (!saved) {
        setState(() {
          _enteredPin = '';
          _pinToConfirm = null;
          _errorMessage = 'PIN could not be saved securely. Try again.';
        });
        return;
      }
      await _securityState.lockApp();
      if (mounted) {
        setState(() {
          _enteredPin = '';
          _pinToConfirm = null;
        });
      }
      return;
    }

    setState(() => _isBusy = true);
    final success = await _securityState.unlockWithPin(_enteredPin);
    if (!mounted) return;
    setState(() => _isBusy = false);
    if (success) {
      widget.onUnlocked();
    } else {
      setState(() {
        _enteredPin = '';
        _errorMessage = 'Incorrect PIN. Please try again.';
      });
    }
  }

  Future<void> _verifyBiometrics() async {
    setState(() {
      _isBusy = true;
      _errorMessage = '';
    });
    final result = await _securityState.unlockWithBiometrics();
    if (!mounted) return;
    setState(() => _isBusy = false);
    switch (result) {
      case BiometricAuthenticationResult.success:
        widget.onUnlocked();
      case BiometricAuthenticationResult.unavailable:
        setState(() => _errorMessage =
            'Biometrics are unavailable. Use your security PIN instead.');
      case BiometricAuthenticationResult.failed:
        setState(() => _errorMessage =
            'Biometric verification failed. Use your security PIN or try again.');
    }
  }

  Future<void> _reauthenticateWebSession() async {
    final reauthenticate = widget.onWebReauthenticate;
    if (reauthenticate == null) {
      setState(
          () => _errorMessage = 'Sign-in is unavailable. Try again later.');
      return;
    }
    setState(() {
      _isBusy = true;
      _errorMessage = '';
    });
    final unlocked = await _securityState.unlockWebSession(reauthenticate);
    if (!mounted) return;
    setState(() => _isBusy = false);
    if (unlocked) {
      widget.onUnlocked();
    } else {
      setState(() => _errorMessage =
          'Identity verification was not completed. Your data remains locked.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color:
                              const Color(0xFF6366F1).withValues(alpha: 0.3)),
                    ),
                    child: Icon(
                      _isWeb ? Icons.lock_clock_outlined : Icons.lock_outline,
                      size: 48,
                      color: const Color(0xFF818CF8),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _heading,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  if (_isWeb) ...[
                    const SizedBox(height: 32),
                    if (_isBusy)
                      const CircularProgressIndicator()
                    else
                      SizedBox(
                        key: const Key('reauthenticate-web-session'),
                        height: 44,
                        width: 240,
                        child: googleSignInButton(
                          onUnsupportedPlatformTap:
                              _reauthenticateWebSession,
                        ),
                      ),
                  ] else ...[
                    const SizedBox(height: 28),
                    _pinDots(),
                    if (_errorMessage.isNotEmpty) _errorText(),
                    const SizedBox(height: 32),
                    _keypad(),
                    const SizedBox(height: 24),
                    TextButton.icon(
                      key: const Key('unlock-with-biometrics'),
                      icon: const Icon(Icons.fingerprint,
                          color: Color(0xFF818CF8)),
                      label: const Text('Unlock with biometrics',
                          style: TextStyle(color: Color(0xFF818CF8))),
                      onPressed: _isBusy ? null : _verifyBiometrics,
                    ),
                  ],
                  if (_isWeb && _errorMessage.isNotEmpty) _errorText(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pinDots() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (index) {
          final filled = index < _enteredPin.length;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? const Color(0xFF818CF8) : const Color(0xFF334155),
              border: Border.all(
                  color: filled ? const Color(0xFF818CF8) : Colors.white24),
            ),
          );
        }),
      );

  Widget _errorText() => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Text(
          _errorMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFF87171), fontSize: 12),
        ),
      );

  Widget _keypad() => GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        mainAxisSpacing: 16,
        crossAxisSpacing: 24,
        childAspectRatio: 1.3,
        children: [
          ...List.generate(9, (index) {
            final digit = '${index + 1}';
            return _buildKey(digit, () => _onKeyPress(digit));
          }),
          _buildIconKey(Icons.fingerprint, _verifyBiometrics,
              color: const Color(0xFF34D399)),
          _buildKey('0', () => _onKeyPress('0')),
          _buildIconKey(Icons.backspace_outlined, _onBackspace,
              color: Colors.white70),
        ],
      );

  Widget _buildKey(String text, VoidCallback onTap) => InkWell(
        onTap: _isBusy ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Text(text,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold)),
        ),
      );

  Widget _buildIconKey(IconData icon, VoidCallback onTap, {Color? color}) =>
      InkWell(
        onTap: _isBusy ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Icon(icon, color: color ?? Colors.white, size: 26),
        ),
      );
}

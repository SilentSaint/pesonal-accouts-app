import 'package:automatic_expense_tracker/services/security_service.dart';
import 'package:automatic_expense_tracker/ui/security_lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryDeviceProtectionStore implements DeviceProtectionStore {
  String? credential;
  bool? locked;
  int? timeout;
  bool? biometricsEnabled;

  @override
  Future<String?> readPinCredential() async => credential;

  @override
  Future<void> writePinCredential(String value) async => credential = value;

  @override
  Future<bool?> readLocked() async => locked;

  @override
  Future<void> writeLocked(bool value) async => locked = value;

  @override
  Future<int?> readIdleTimeoutMinutes() async => timeout;

  @override
  Future<void> writeIdleTimeoutMinutes(int value) async => timeout = value;

  @override
  Future<bool?> readBiometricsEnabled() async => biometricsEnabled;

  @override
  Future<void> writeBiometricsEnabled(bool value) async =>
      biometricsEnabled = value;
}

class FakeBiometricAuthenticator implements BiometricAuthenticator {
  FakeBiometricAuthenticator({
    this.available = true,
    this.authenticated = true,
  });

  bool available;
  bool authenticated;

  @override
  Future<bool> authenticate() async => authenticated;

  @override
  Future<bool> isAvailable() async => available;
}

SecurityState mobileState(
  MemoryDeviceProtectionStore store,
  FakeBiometricAuthenticator biometrics,
) => SecurityState.forTesting(
  store: store,
  biometrics: biometrics,
  platform: ProtectionPlatform.mobile,
);

void main() {
  group('SecurityState', () {
    late MemoryDeviceProtectionStore store;
    late FakeBiometricAuthenticator biometrics;
    late SecurityState state;

    setUp(() async {
      store = MemoryDeviceProtectionStore();
      biometrics = FakeBiometricAuthenticator();
      state = mobileState(store, biometrics);
      await state.initialize();
    });

    tearDown(() => state.cancelIdleTimer());

    test(
      'starts mobile locked and securely persists a non-default PIN',
      () async {
        expect(state.isLocked, isTrue);
        expect(state.hasPin, isFalse);

        expect(await state.setCustomPin('12a4'), isFalse);
        expect(await state.setCustomPin('5678'), isTrue);
        expect(store.credential, isNot(contains('5678')));
        expect(store.credential, contains('"salt"'));
        expect(store.credential, contains('"hash"'));

        expect(await state.unlockWithPin('1234'), isFalse);
        expect(await state.unlockWithPin('5678'), isTrue);
        expect(state.isLocked, isFalse);
      },
    );

    test(
      'uses the biometric adapter and preserves lock on unavailable or failed authentication',
      () async {
        biometrics.available = false;
        expect(
          await state.unlockWithBiometrics(),
          BiometricAuthenticationResult.unavailable,
        );
        expect(state.isLocked, isTrue);

        biometrics.available = true;
        biometrics.authenticated = false;
        expect(
          await state.unlockWithBiometrics(),
          BiometricAuthenticationResult.failed,
        );
        expect(state.isLocked, isTrue);

        biometrics.authenticated = true;
        expect(
          await state.unlockWithBiometrics(),
          BiometricAuthenticationResult.success,
        );
        expect(state.isLocked, isFalse);
      },
    );

    test('locks mobile data when the app enters the background', () async {
      await state.setCustomPin('5678');
      await state.unlockWithPin('5678');
      expect(state.isLocked, isFalse);

      state.onAppLifecycleChanged(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);

      expect(state.isLocked, isTrue);
      expect(store.locked, isTrue);
    });

    test('locks after configured inactivity', () async {
      final timedState = SecurityState.forTesting(
        store: store,
        biometrics: biometrics,
        platform: ProtectionPlatform.web,
        timeoutDuration: (_) => const Duration(milliseconds: 10),
      );
      addTearDown(timedState.cancelIdleTimer);
      await timedState.initialize();
      expect(await timedState.setIdleTimeout(1), isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(timedState.isLocked, isTrue);
      expect(store.locked, isTrue);
    });

    test(
      'web lock survives reload and requires successful reauthentication',
      () async {
        final webState = SecurityState.forTesting(
          store: store,
          biometrics: biometrics,
          platform: ProtectionPlatform.web,
        );
        addTearDown(webState.cancelIdleTimer);
        await webState.initialize();
        expect(webState.isLocked, isFalse);
        await webState.lockApp();

        final reloadedWebState = SecurityState.forTesting(
          store: store,
          biometrics: biometrics,
          platform: ProtectionPlatform.web,
        );
        addTearDown(reloadedWebState.cancelIdleTimer);
        await reloadedWebState.initialize();
        expect(reloadedWebState.isLocked, isTrue);

        expect(
          await reloadedWebState.unlockWebSession(() async => false),
          isFalse,
        );
        expect(reloadedWebState.isLocked, isTrue);
        expect(
          await reloadedWebState.unlockWebSession(() async => true),
          isTrue,
        );
        expect(reloadedWebState.isLocked, isFalse);
      },
    );

    test(
      'uses a longer default web idle timeout for the authenticated session',
      () async {
        final webState = SecurityState.forTesting(
          store: store,
          biometrics: biometrics,
          platform: ProtectionPlatform.web,
        );
        addTearDown(webState.cancelIdleTimer);

        await webState.initialize();

        expect(
          webState.idleTimeoutMinutes,
          SecurityState.defaultWebIdleTimeoutMinutes,
        );
        expect(webState.idleTimeoutMinutes, 30);
      },
    );
  });

  testWidgets(
    'mobile lock screen rejects a bad PIN and unlocks with the configured PIN',
    (tester) async {
      final store = MemoryDeviceProtectionStore();
      final state = mobileState(store, FakeBiometricAuthenticator());
      addTearDown(state.cancelIdleTimer);
      await state.initialize();
      await state.setCustomPin('5678');

      var unlocked = false;
      await tester.pumpWidget(
        MaterialApp(
          home: SecurityLockScreen(
            securityState: state,
            onUnlocked: () => unlocked = true,
          ),
        ),
      );
      await tester.pump();

      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      expect(unlocked, isFalse);
      expect(find.text('Incorrect PIN. Please try again.'), findsOneWidget);

      for (final digit in ['5', '6', '7', '8']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      expect(unlocked, isTrue);
      state.cancelIdleTimer();
    },
  );

  testWidgets(
    'web lock screen keeps data locked when identity verification fails',
    (tester) async {
      final state = SecurityState.forTesting(
        store: MemoryDeviceProtectionStore(),
        biometrics: FakeBiometricAuthenticator(),
        platform: ProtectionPlatform.web,
      );
      addTearDown(state.cancelIdleTimer);
      await state.initialize();
      await state.lockApp();
      var unlocked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: SecurityLockScreen(
            securityState: state,
            onUnlocked: () => unlocked = true,
            onWebReauthenticate: () async => false,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('reauthenticate-web-session')));
      await tester.pump();

      expect(unlocked, isFalse);
      expect(state.isLocked, isTrue);
      expect(
        find.text(
          'Identity verification was not completed. Your data remains locked.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'web lock screen reveals data only after identity verification succeeds',
    (tester) async {
      final state = SecurityState.forTesting(
        store: MemoryDeviceProtectionStore(),
        biometrics: FakeBiometricAuthenticator(),
        platform: ProtectionPlatform.web,
      );
      addTearDown(state.cancelIdleTimer);
      await state.initialize();
      await state.lockApp();
      var unlocked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: SecurityLockScreen(
            securityState: state,
            onUnlocked: () => unlocked = true,
            onWebReauthenticate: () async => true,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('reauthenticate-web-session')));
      await tester.pump();

      expect(unlocked, isTrue);
      expect(state.isLocked, isFalse);
      state.cancelIdleTimer();
    },
  );
}

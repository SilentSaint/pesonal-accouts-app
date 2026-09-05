import 'package:automatic_expense_tracker/services/authentication_session_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invalidates an in-flight authentication operation after sign-out', () {
    final guard = AuthenticationSessionGuard();
    final inFlightSignIn = guard.beginOperation();

    guard.invalidate();

    expect(guard.isCurrent(inFlightSignIn), isFalse);
  });

  test('keeps the current authentication operation valid', () {
    final guard = AuthenticationSessionGuard();
    final operation = guard.beginOperation();

    expect(guard.isCurrent(operation), isTrue);
  });
}

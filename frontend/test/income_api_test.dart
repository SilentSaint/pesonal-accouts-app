import 'dart:convert';

import 'package:automatic_expense_tracker/services/backend_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('loads confirmed income sources and unconfirmed suggestions', () async {
    SharedPreferences.setMockInitialValues({});
    late http.Request captured;
    final service = BackendApiService.forTesting(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
            jsonEncode({
              'sources': [_sourceJson('income-1', 'CONFIRMED')],
              'suggestions': [
                {
                  'source': _sourceJson('candidate-1', 'PENDING'),
                  'confidence': 0.95
                }
              ],
            }),
            200);
      }),
      preferences: SharedPreferences.getInstance,
    );

    final incomes = await service.fetchIncomeSources();

    expect(captured.url.path, '/v2/income-sources');
    expect(incomes.sources.single.name, 'Acme Payroll');
    expect(incomes.suggestions.single.confidence, 0.95);
  });
}

Map<String, dynamic> _sourceJson(String id, String status) => {
      'id': id,
      'name': 'Acme Payroll',
      'type': 'FIXED',
      'amount': '75000.00',
      'currency': 'INR',
      'cadence': 'MONTHLY',
      'effectiveFrom': '2026-01-31',
      'effectiveTo': null,
      'linkedAccountId': 'account-1',
      'confirmationStatus': status,
      'sourceTransactionIds': ['salary-jan'],
    };

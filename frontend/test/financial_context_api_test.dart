import 'dart:convert';

import 'package:automatic_expense_tracker/services/backend_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('loads authoritative context at the requested as-of time', () async {
    SharedPreferences.setMockInitialValues({});
    late http.Request captured;
    final service = BackendApiService.forTesting(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
            jsonEncode({
              'asOf': '2026-08-29T10:00:00Z',
              'items': [_itemJson()],
            }),
            200);
      }),
      preferences: SharedPreferences.getInstance,
    );

    final context = await service.fetchFinancialContext(
        asOf: DateTime.utc(2026, 8, 29, 10));

    expect(captured.url.path, '/v2/financial-context');
    expect(captured.url.queryParameters['asOf'], '2026-08-29T10:00:00.000Z');
    expect(context.items.single.provenance, 'USER_DECLARED');
    expect(context.items.single.status, 'ACTIVE');
    expect(context.items.single.effectiveFrom, DateTime.utc(2026, 8, 1));
  });
}

Map<String, dynamic> _itemJson() => {
      'id': 'ctx-cash-floor',
      'type': 'PREFERRED_MINIMUM_CASH_BALANCE',
      'label': 'Cash floor',
      'values': {'amount': '25000.00', 'currency': 'INR'},
      'capabilities': ['CASH_FLOW_FORECAST'],
      'provenance': 'USER_DECLARED',
      'active': true,
      'effectiveFrom': '2026-08-01',
      'createdAt': '2026-08-01T10:00:00Z',
      'updatedAt': '2026-08-01T10:00:00Z',
      'status': 'ACTIVE',
      'conflictIds': [],
    };

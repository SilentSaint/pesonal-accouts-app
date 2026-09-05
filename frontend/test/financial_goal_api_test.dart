import 'dart:convert';

import 'package:automatic_expense_tracker/services/backend_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
      'loads server-authoritative goal projections at the requested as-of date',
      () async {
    SharedPreferences.setMockInitialValues({});
    late http.Request captured;
    final service = BackendApiService.forTesting(
      client: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode(_goalListJson()), 200);
      }),
      preferences: SharedPreferences.getInstance,
    );

    final goals =
        await service.fetchFinancialGoals(asOf: DateTime.utc(2026, 3, 1));

    expect(captured.url.path, '/v2/financial-goals');
    expect(captured.url.queryParameters['asOf'], '2026-03-01');
    expect(goals.goals.single.projection!.formulaVersion, '1.0.0');
    expect(goals.goals.single.projection!.status, 'AT_RISK');
  });
}

Map<String, dynamic> _goalListJson() => {
      'asOf': '2026-03-01',
      'goals': [
        {
          'id': 'car',
          'name': 'Car',
          'targetAmount': '1200.00',
          'currency': 'INR',
          'targetDate': '2026-06-30',
          'priority': 'HIGH',
          'lifecycle': 'ACTIVE',
          'allocations': [],
          'contributionRule': null,
          'contributions': [],
          'projection': {
            'classification': 'PREDICTION',
            'asOf': '2026-03-01T00:00:00Z',
            'freshnessAsOf': '2026-03-01T00:00:00Z',
            'formula': {'id': 'financial-goal-projection', 'version': '1.0.0'},
            'confidence': '0.25',
            'sourceCount': 0,
            'assumptions': [],
            'warnings': ['INSUFFICIENT_HISTORY'],
            'filters': {'goalId': 'provided in route'},
            'comparisonBaseline': null,
            'value': {
              'amountRemaining': '1200.00',
              'currency': 'INR',
              'monthsRemaining': 4,
              'requiredMonthlyContribution': '300.00',
              'observedMonthlyContribution': '0.00',
              'projectedCompletionDate': null,
              'monthlyShortfallOrSurplus': '-300.00',
              'minimumBalanceBreached': false,
              'status': 'AT_RISK',
              'contributionEvidenceReferences': [],
            },
          },
        },
      ],
    };

import 'dart:convert';

import 'package:automatic_expense_tracker/services/conversational_query_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('posts a question to the versioned conversational query route',
      () async {
    late http.Request captured;
    final service = ConversationalQueryService(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'status': 'ANSWER',
            'observation':
                'Personal spending for the selected period is INR 300.00.',
            'asOf': '2026-08-31T18:30:00Z',
            'sourceCount': 2,
            'drillDown': {
              'start': '2026-08-01',
              'end': '2026-08-31',
              'currency': 'INR',
              'accountIds': [],
              'categoryId': '',
              'merchantName': '',
            },
          }),
          200,
        );
      }),
      baseUrl: 'https://example.test/api',
    );

    final answer = await service.ask('How much did I spend this month?');

    expect(captured.method, 'POST');
    expect(captured.url.path, '/v2/finance-queries');
    expect(jsonDecode(captured.body),
        {'question': 'How much did I spend this month?'});
    expect(answer.observation,
        'Personal spending for the selected period is INR 300.00.');
    expect(answer.drillDown?.start, '2026-08-01');
  });
}

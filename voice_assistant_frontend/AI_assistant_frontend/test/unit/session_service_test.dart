import 'dart:convert';

import 'package:ai_assistant_frontend/core/network/api_client.dart';
import 'package:ai_assistant_frontend/core/utils/result.dart';
import 'package:ai_assistant_frontend/services/session_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import '../helpers/fakes.dart';

void main() {
  group('SessionService', () {
    test('cancelSession posts to the session cancellation endpoint', () async {
      final api = ApiClient.withClient(MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/sessions/session-1/cancel');
        expect(jsonDecode(request.body), isEmpty);
        return jsonResponse({'status': 'CANCELLED'});
      }));

      final result = await SessionService(api: api).cancelSession('session-1');

      expect(result, isA<Success<void>>());
    });

    test('cancelSession returns backend errors', () async {
      final api = ApiClient.withClient(MockClient((request) async {
        expect(request.url.path, '/api/sessions/session-1/cancel');
        return jsonResponse(
          {'message': 'Session not found'},
          status: 404,
        );
      }));

      final result = await SessionService(api: api).cancelSession('session-1');

      expect(result, isA<Failure<void>>());
      expect((result as Failure<void>).message, 'Session not found');
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:ai_assistant_frontend/core/network/api_client.dart';
import 'package:ai_assistant_frontend/core/utils/result.dart';
import 'package:ai_assistant_frontend/core/utils/secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/fakes.dart';

void main() {
  setUp(() {
    SecureStorage.instance = SecureStorage.inMemory();
  });

  tearDown(() {
    SecureStorage.reset();
  });

  test('decodes a successful JSON response into Success', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/recipes');
      return jsonResponse({'items': [], 'ok': true});
    });
    final api = ApiClient.withClient(client);

    final result = await api.get('/api/recipes');

    expect(result, isA<Success<dynamic>>());
    expect((result as Success).data, {'items': [], 'ok': true});
  });

  test('treats an empty 200 body as an empty map', () async {
    final api = ApiClient.withClient(MockClient((_) async => http.Response('', 200)));

    final result = await api.get('/api/anything');

    expect(result, isA<Success<dynamic>>());
    expect((result as Success).data, <String, dynamic>{});
  });

  test('keeps a non-JSON body as a raw string', () async {
    final api = ApiClient.withClient(
      MockClient((_) async => http.Response('plain text', 200)),
    );

    final result = await api.get('/api/anything');

    expect((result as Success).data, 'plain text');
  });

  test('surfaces the backend message for an error status', () async {
    final api = ApiClient.withClient(
      MockClient((_) async => jsonResponse({'message': 'Invalid credentials'}, status: 401)),
    );

    final result = await api.post('/api/auth/login', body: {});

    expect(result, isA<Failure<dynamic>>());
    expect((result as Failure).message, 'Invalid credentials');
  });

  test('falls back to a generic message when the error body has none', () async {
    final api = ApiClient.withClient(
      MockClient((_) async => http.Response('boom', 500)),
    );

    final result = await api.get('/api/anything');

    expect((result as Failure).message, 'Request failed (500)');
  });

  test('attaches the bearer token when one is stored', () async {
    await SecureStorage.instance.saveSession(accessToken: 'jwt-token');
    String? authorization;
    final api = ApiClient.withClient(MockClient((request) async {
      authorization = request.headers['Authorization'];
      return jsonResponse({});
    }));

    await api.get('/api/private');

    expect(authorization, 'Bearer jwt-token');
  });

  test('omits the bearer token when auth is disabled', () async {
    await SecureStorage.instance.saveSession(accessToken: 'jwt-token');
    String? authorization;
    final api = ApiClient.withClient(MockClient((request) async {
      authorization = request.headers['Authorization'];
      return jsonResponse({});
    }));

    await api.post('/api/auth/login', body: {}, auth: false);

    expect(authorization, isNull);
  });

  test('serialises query parameters', () async {
    late Uri requested;
    final api = ApiClient.withClient(MockClient((request) async {
      requested = request.url;
      return jsonResponse([]);
    }));

    await api.get('/api/recipes', query: {'search': 'paneer', 'sort': 'time_asc'});

    expect(requested.queryParameters['search'], 'paneer');
    expect(requested.queryParameters['sort'], 'time_asc');
  });

  test('maps a SocketException to a friendly offline message', () async {
    final api = ApiClient.withClient(MockClient((_) async {
      throw const SocketException('down');
    }));

    final result = await api.get('/api/recipes');

    expect((result as Failure).message, 'No internet connection. Please check your network.');
  });

  test('sends and decodes JSON bodies for PUT and DELETE', () async {
    final seen = <String, String>{};
    final api = ApiClient.withClient(MockClient((request) async {
      seen[request.method] = request.body;
      return jsonResponse({'ok': true});
    }));

    final put = await api.put('/api/x', body: {'a': 1});
    final delete = await api.delete('/api/x');

    expect(put, isA<Success<dynamic>>());
    expect(delete, isA<Success<dynamic>>());
    expect(jsonDecode(seen['PUT']!), {'a': 1});
    expect(seen['DELETE'], '');
  });
}

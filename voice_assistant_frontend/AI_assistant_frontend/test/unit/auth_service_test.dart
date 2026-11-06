import 'dart:convert';

import 'package:ai_assistant_frontend/core/network/api_client.dart';
import 'package:ai_assistant_frontend/core/utils/result.dart';
import 'package:ai_assistant_frontend/core/utils/secure_storage.dart';
import 'package:ai_assistant_frontend/models/user_model.dart';
import 'package:ai_assistant_frontend/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import '../helpers/fakes.dart';

void main() {
  setUp(() {
    SecureStorage.instance = SecureStorage.inMemory();
  });

  tearDown(() {
    SecureStorage.reset();
  });

  test('login persists the token, user id and username', () async {
    late Map<String, dynamic> sent;
    final api = ApiClient.withClient(MockClient((request) async {
      expect(request.url.path, '/api/auth/login');
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return jsonResponse({
        'token': 'jwt-123',
        'userId': 'u-1',
        'username': 'chef',
      });
    }));

    final result = await AuthService(api: api).login(username: 'chef', password: 'secret1');

    expect(result, isA<Success<UserModel>>());
    final user = (result as Success<UserModel>).data;
    expect(user.id, 'u-1');
    expect(user.username, 'chef');
    expect(sent, {'username': 'chef', 'password': 'secret1'});
    expect(await SecureStorage.instance.accessToken, 'jwt-123');
    expect(await SecureStorage.instance.userId, 'u-1');
    expect(await SecureStorage.instance.userName, 'chef');
  });

  test('login accepts accessToken and jwt aliases', () async {
    final api = ApiClient.withClient(MockClient((_) async => jsonResponse({
          'accessToken': 'access-token',
          'username': 'chef',
        })));

    final result = await AuthService(api: api).login(username: 'chef', password: 'secret1');

    expect(result, isA<Success<UserModel>>());
    expect(await SecureStorage.instance.accessToken, 'access-token');
  });

  test('login fails clearly when no token is returned', () async {
    final api = ApiClient.withClient(
      MockClient((_) async => jsonResponse({'userId': 'u-1', 'username': 'chef'})),
    );

    final result = await AuthService(api: api).login(username: 'chef', password: 'secret1');

    expect(result, isA<Failure<UserModel>>());
    expect((result as Failure).message, 'Login succeeded but no token was returned.');
    expect(await SecureStorage.instance.accessToken, isNull);
  });

  test('login propagates the backend error message', () async {
    final api = ApiClient.withClient(
      MockClient((_) async => jsonResponse({'message': 'Bad credentials'}, status: 401)),
    );

    final result = await AuthService(api: api).login(username: 'chef', password: 'nope');

    expect((result as Failure).message, 'Bad credentials');
  });

  test('register posts username, email and password and saves the session', () async {
    late Map<String, dynamic> sent;
    final api = ApiClient.withClient(MockClient((request) async {
      expect(request.url.path, '/api/auth/register');
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return jsonResponse({'token': 't', 'userId': 'u-2', 'username': 'newchef'});
    }));

    final result = await AuthService(api: api).register(
      username: 'newchef',
      email: 'new@example.com',
      password: 'secret1',
    );

    expect(result, isA<Success<UserModel>>());
    expect(sent, {
      'username': 'newchef',
      'email': 'new@example.com',
      'password': 'secret1',
    });
    expect(await SecureStorage.instance.accessToken, 't');
  });

  test('logout clears every stored credential and isLoggedIn flips', () async {
    final service = AuthService(
      api: ApiClient.withClient(MockClient((_) async => jsonResponse({}))),
    );
    await SecureStorage.instance.saveSession(
      accessToken: 't',
      refreshToken: 'r',
      userId: 'u',
      userName: 'chef',
      userUsername: 'chef',
    );

    expect(await service.isLoggedIn, isTrue);

    await service.logout();

    expect(await service.isLoggedIn, isFalse);
    expect(await SecureStorage.instance.refreshToken, isNull);
    expect(await SecureStorage.instance.userId, isNull);
    expect(await SecureStorage.instance.userName, isNull);
  });

  test('isLoggedIn is false without a stored token', () async {
    final service = AuthService(
      api: ApiClient.withClient(MockClient((_) async => jsonResponse({}))),
    );
    expect(await service.isLoggedIn, isFalse);
  });
}

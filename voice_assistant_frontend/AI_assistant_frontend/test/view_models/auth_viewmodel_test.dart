import 'package:ai_assistant_frontend/core/network/api_client.dart';
import 'package:ai_assistant_frontend/core/utils/secure_storage.dart';
import 'package:ai_assistant_frontend/services/auth_service.dart';
import 'package:ai_assistant_frontend/view_models/auth_viewmodel.dart';
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

  AuthViewModel buildViewModel(MockClient client) =>
      AuthViewModel(authService: AuthService(api: ApiClient.withClient(client)));

  test('starts idle', () {
    final vm = buildViewModel(MockClient((_) async => jsonResponse({})));

    expect(vm.status, AuthStatus.idle);
    expect(vm.isLoading, isFalse);
    expect(vm.errorMessage, isNull);
    expect(vm.currentUser, isNull);
  });

  test('login sets loading synchronously, then success and notifies', () async {
    final vm = buildViewModel(MockClient((_) async => jsonResponse({
          'token': 't',
          'userId': 'u-1',
          'username': 'chef',
        })));
    var notifications = 0;
    vm.addListener(() => notifications++);

    final future = vm.login('chef', 'secret1');

    expect(vm.status, AuthStatus.loading);
    expect(vm.isLoading, isTrue);

    final ok = await future;

    expect(ok, isTrue);
    expect(vm.status, AuthStatus.success);
    expect(vm.currentUser?.username, 'chef');
    expect(vm.errorMessage, isNull);
    expect(notifications, greaterThanOrEqualTo(2));
  });

  test('login failure records the message and returns false', () async {
    final vm = buildViewModel(
      MockClient((_) async => jsonResponse({'message': 'Bad credentials'}, status: 401)),
    );

    final ok = await vm.login('chef', 'wrong');

    expect(ok, isFalse);
    expect(vm.status, AuthStatus.error);
    expect(vm.errorMessage, 'Bad credentials');
    expect(vm.currentUser, isNull);
  });

  test('register success stores the user', () async {
    final vm = buildViewModel(MockClient((_) async => jsonResponse({
          'token': 't',
          'userId': 'u-2',
          'username': 'newchef',
        })));

    final ok = await vm.register('newchef', 'new@example.com', 'secret1');

    expect(ok, isTrue);
    expect(vm.status, AuthStatus.success);
    expect(vm.currentUser?.id, 'u-2');
    expect(await SecureStorage.instance.accessToken, 't');
  });

  test('register failure sets the error state', () async {
    final vm = buildViewModel(
      MockClient((_) async => jsonResponse({'message': 'Username taken'}, status: 409)),
    );

    final ok = await vm.register('chef', 'c@example.com', 'secret1');

    expect(ok, isFalse);
    expect(vm.status, AuthStatus.error);
    expect(vm.errorMessage, 'Username taken');
  });

  test('logout clears the session and returns to idle', () async {
    final vm = buildViewModel(MockClient((_) async => jsonResponse({
          'token': 't',
          'userId': 'u-1',
          'username': 'chef',
        })));
    await vm.login('chef', 'secret1');

    await vm.logout();

    expect(vm.status, AuthStatus.idle);
    expect(vm.currentUser, isNull);
    expect(await SecureStorage.instance.accessToken, isNull);
  });
}

import 'package:ai_assistant_frontend/core/utils/secure_storage.dart';
import 'package:ai_assistant_frontend/view_models/home_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loadUser reads the stored display name', () async {
    final storage = SecureStorage.inMemory();
    await storage.saveSession(accessToken: 't', userName: 'Harsh Chef');
    final vm = HomeViewModel(storage: storage);

    await vm.loadUser();

    expect(vm.userName, 'Harsh Chef');
  });

  test('loadUser falls back to Chef when nothing is stored', () async {
    final vm = HomeViewModel(storage: SecureStorage.inMemory());

    await vm.loadUser();

    expect(vm.userName, 'Chef');
  });

  test('loadUser notifies listeners', () async {
    final vm = HomeViewModel(storage: SecureStorage.inMemory());
    var notifications = 0;
    vm.addListener(() => notifications++);

    await vm.loadUser();

    expect(notifications, 1);
  });
}

import 'package:ai_assistant_frontend/core/utils/secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SecureStorage storage;

  setUp(() {
    storage = SecureStorage.inMemory();
  });

  test('defaults stoves to 1 and servings to 2', () async {
    expect(await storage.stoveCount, 1);
    expect(await storage.servingCount, 2);
  });

  test('persists and reads the full session', () async {
    await storage.saveSession(
      accessToken: 'a',
      refreshToken: 'r',
      userName: 'Chef',
      userUsername: 'chef',
      userEmail: 'chef@example.com',
      userId: 'u-1',
    );

    expect(await storage.accessToken, 'a');
    expect(await storage.refreshToken, 'r');
    expect(await storage.userName, 'Chef');
    expect(await storage.userUsername, 'chef');
    expect(await storage.userEmail, 'chef@example.com');
    expect(await storage.userId, 'u-1');
  });

  test('optional session fields are left untouched when omitted', () async {
    await storage.saveSession(accessToken: 'a', userName: 'Chef');
    await storage.saveSession(accessToken: 'b');

    expect(await storage.accessToken, 'b');
    expect(await storage.userName, 'Chef');
    expect(await storage.userEmail, isNull);
    expect(await storage.refreshToken, isNull);
  });

  test('persists kitchen settings', () async {
    await storage.saveSettings(stoves: 4, servings: 6);

    expect(await storage.stoveCount, 4);
    expect(await storage.servingCount, 6);
  });

  test('clear removes everything', () async {
    await storage.saveSession(accessToken: 'a', userName: 'Chef');
    await storage.saveSettings(stoves: 3, servings: 4);

    await storage.clear();

    expect(await storage.accessToken, isNull);
    expect(await storage.userName, isNull);
    expect(await storage.stoveCount, 1);
    expect(await storage.servingCount, 2);
  });
}

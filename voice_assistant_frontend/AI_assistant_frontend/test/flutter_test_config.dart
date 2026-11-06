import 'dart:async';

import 'package:ai_assistant_frontend/core/utils/secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs before every test in this package. Initializes the Flutter binding and
/// swaps the platform-backed secure storage for an in-memory implementation so
/// no plugin channel is required.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SecureStorage.instance = SecureStorage.inMemory();
  await testMain();
}

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thin wrapper around secure storage so the rest of the app never talks
/// to the plugin directly (easy to swap/mock in tests).
///
/// Tests can swap [instance] with [SecureStorage.inMemory] which keeps
/// everything in a plain map and never touches the platform channel.
class SecureStorage {
  SecureStorage._(this._storage);
  SecureStorage.inMemory() : _storage = null;

  static SecureStorage instance = SecureStorage._(const FlutterSecureStorage());

  /// Restores the real platform-backed store. Call in `tearDown`.
  @visibleForTesting
  static void reset() {
    instance = SecureStorage._(const FlutterSecureStorage());
  }

  final FlutterSecureStorage? _storage;
  final Map<String, String> _memory = {};

  static const _keyAccessToken = 'access_token';
  static const _keyRefreshToken = 'refresh_token';
  static const _keyUserName = 'user_name';
  static const _keyUserUsername = 'user_username';
  static const _keyUserEmail = 'user_email';
  static const _keyUserId = 'user_id';
  static const _keyStoveCount = 'stove_count';
  static const _keyServingCount = 'serving_count';

  Future<void> _write(String key, String? value) async {
    if (_storage == null) {
      if (value == null) {
        _memory.remove(key);
      } else {
        _memory[key] = value;
      }
      return;
    }
    await _storage.write(key: key, value: value);
  }

  Future<String?> _read(String key) async {
    if (_storage == null) return _memory[key];
    return _storage.read(key: key);
  }

  Future<void> saveSession({
    required String accessToken,
    String? refreshToken,
    String? userName,
    String? userUsername,
    String? userEmail,
    String? userId,
  }) async {
    await _write(_keyAccessToken, accessToken);
    if (refreshToken != null) await _write(_keyRefreshToken, refreshToken);
    if (userName != null) await _write(_keyUserName, userName);
    if (userUsername != null) await _write(_keyUserUsername, userUsername);
    if (userEmail != null) await _write(_keyUserEmail, userEmail);
    if (userId != null) await _write(_keyUserId, userId);
  }

  Future<void> saveSettings(
      {required int stoves, required int servings}) async {
    await _write(_keyStoveCount, stoves.toString());
    await _write(_keyServingCount, servings.toString());
  }

  Future<String?> get accessToken => _read(_keyAccessToken);
  Future<String?> get refreshToken => _read(_keyRefreshToken);
  Future<String?> get userName => _read(_keyUserName);
  Future<String?> get userUsername => _read(_keyUserUsername);
  Future<String?> get userEmail => _read(_keyUserEmail);
  Future<String?> get userId => _read(_keyUserId);
  Future<int> get stoveCount async =>
      int.tryParse(await _read(_keyStoveCount) ?? '1') ?? 1;
  Future<int> get servingCount async =>
      int.tryParse(await _read(_keyServingCount) ?? '2') ?? 2;

  Future<void> clear() async {
    if (_storage == null) {
      _memory.clear();
      return;
    }
    await _storage.deleteAll();
  }
}

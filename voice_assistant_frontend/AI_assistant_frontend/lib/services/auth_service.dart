import '../core/constants/api_constants.dart';
import '../core/network/api_client.dart';
import '../core/utils/result.dart';
import '../core/utils/secure_storage.dart';
import '../models/user_model.dart';

class AuthService {
  AuthService({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  Future<Result<UserModel>> login(
      {required String username, required String password}) async {
    final res = await _api.post(ApiConstants.login,
        body: {'username': username, 'password': password}, auth: false);
    return switch (res) {
      Success(data: final data) =>
        await _persistAndReturnUser(data as Map<String, dynamic>),
      Failure(message: final m) => Failure(m),
    };
  }

  Future<Result<UserModel>> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final res = await _api.post(
      ApiConstants.register,
      body: {'username': username, 'email': email, 'password': password},
      auth: false,
    );
    return switch (res) {
      Success(data: final data) =>
        await _persistAndReturnUser(data as Map<String, dynamic>),
      Failure(message: final m) => Failure(m),
    };
  }

  Future<Result<UserModel>> _persistAndReturnUser(
      Map<String, dynamic> data) async {
    final token =
        (data['token'] ?? data['accessToken'] ?? data['jwt'] ?? '').toString();
    if (token.isEmpty)
      return const Failure('Login succeeded but no token was returned.');

    // AuthResponse has userId and username
    final user = UserModel(
      id: (data['userId'] ?? '').toString(),
      name: (data['username'] ?? 'User').toString(),
      username: (data['username'] ?? '').toString(),
      email: data['email']?.toString(),
    );

    await SecureStorage.instance.saveSession(
      accessToken: token,
      userName: user.name,
      userUsername: user.username,
      userEmail: user.email,
      userId: user.id,
    );
    return Success(user);
  }

  Future<void> logout() async {
    // There is no logout endpoint in the current API spec, so we just clear the local session.
    await SecureStorage.instance.clear();
  }

  Future<bool> get isLoggedIn async =>
      (await SecureStorage.instance.accessToken)?.isNotEmpty ?? false;
}

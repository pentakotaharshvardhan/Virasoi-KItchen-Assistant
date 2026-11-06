import '../core/constants/api_constants.dart';
import '../core/network/api_client.dart';
import '../core/utils/result.dart';
import '../core/utils/secure_storage.dart';

class SessionService {
  SessionService({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  Future<Result<Map<String, dynamic>>> startSession({required int numberOfStoves}) async {
    final userId = await SecureStorage.instance.userId;
    final res = await _api.post(ApiConstants.startSession, body: {
      'userId': userId,
      'numberOfStoves': numberOfStoves,
    });
    return switch (res) {
      Success(data: final data) => Success(data as Map<String, dynamic>),
      Failure(message: final m) => Failure(m),
    };
  }

  Future<Result<void>> addDish(String sessionId, {required String dishName, required int servesRequested}) async {
    final res = await _api.post(ApiConstants.sessionDishes(sessionId), body: {
      'dishName': dishName,
      'servesRequested': servesRequested,
    });
    return switch (res) {
      Success() => const Success(null),
      Failure(message: final m) => Failure(m),
    };
  }
}

import 'package:flutter/material.dart';
import '../core/utils/result.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

enum AuthStatus { idle, loading, success, error }

class AuthViewModel extends ChangeNotifier {
  AuthViewModel({AuthService? authService}) : _authService = authService ?? AuthService();

  final AuthService _authService;

  AuthStatus status = AuthStatus.idle;
  String? errorMessage;
  UserModel? currentUser;

  bool get isLoading => status == AuthStatus.loading;

  Future<bool> login(String username, String password) async {
    status = AuthStatus.loading;
    errorMessage = null;
    notifyListeners();

    final result = await _authService.login(username: username, password: password);
    switch (result) {
      case Success(data: final user):
        currentUser = user;
        status = AuthStatus.success;
        notifyListeners();
        return true;
      case Failure(message: final m):
        errorMessage = m;
        status = AuthStatus.error;
        notifyListeners();
        return false;
    }
  }

  Future<bool> register(String username, String email, String password) async {
    status = AuthStatus.loading;
    errorMessage = null;
    notifyListeners();

    final result = await _authService.register(username: username, email: email, password: password);
    switch (result) {
      case Success(data: final user):
        currentUser = user;
        status = AuthStatus.success;
        notifyListeners();
        return true;
      case Failure(message: final m):
        errorMessage = m;
        status = AuthStatus.error;
        notifyListeners();
        return false;
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    currentUser = null;
    status = AuthStatus.idle;
    notifyListeners();
  }
}

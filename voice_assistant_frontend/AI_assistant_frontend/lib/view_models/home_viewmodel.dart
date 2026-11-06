import 'package:flutter/material.dart';
import '../core/utils/secure_storage.dart';

class HomeViewModel extends ChangeNotifier {
  HomeViewModel({SecureStorage? storage}) : _storage = storage ?? SecureStorage.instance;

  final SecureStorage _storage;
  String userName = '';
  String userEmail = '';

  Future<void> loadUser() async {
    userName = await _storage.userName ?? 'Chef';
    //userEmail = await SecureStorage.instance.userEmail ?? '';
    notifyListeners();
  }
}

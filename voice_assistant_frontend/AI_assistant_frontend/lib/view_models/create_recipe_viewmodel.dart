import 'dart:async';
import 'package:flutter/material.dart';
import '../core/utils/result.dart';
import '../core/utils/secure_storage.dart';
import '../models/recipe_model.dart';
import '../services/recipe_service.dart';
import '../services/ai_service.dart';

class CreateRecipeViewModel extends ChangeNotifier {
  static const int maxStoves = 4;
  static const int maxDishes = 4;

  CreateRecipeViewModel({
    RecipeService? service,
    AiService? aiService,
    SecureStorage? storage,
  })  : _service = service ?? RecipeService(),
        _ai = aiService ?? AiService(),
        _storage = storage ?? SecureStorage.instance;

  final RecipeService _service;
  final AiService _ai;
  final SecureStorage _storage;

  bool isSubmitting = false;
  String? errorMessage;
  List<RecipeModel> generated = [];

  List<String> selectedDishes = [];
  String suggestedDishName = '';
  int stoves = 1;
  int servings = 2;

  Timer? _suggestTimer;

  Future<void> init() async {
    final storedStoveCount = await _storage.stoveCount;
    stoves = storedStoveCount < 1
        ? 1
        : storedStoveCount > maxStoves
            ? maxStoves
            : storedStoveCount;
    servings = await _storage.servingCount;
    notifyListeners();
  }

  bool addDish(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return false;
    if (selectedDishes.contains(clean)) return true;
    if (selectedDishes.length >= maxDishes) {
      _suggestTimer?.cancel();
      suggestedDishName = '';
      errorMessage = 'You can add up to $maxDishes dishes.';
      notifyListeners();
      return false;
    }

    selectedDishes.add(clean);
    suggestedDishName = '';
    errorMessage = null;
    notifyListeners();
    return true;
  }

  void removeDish(String name) {
    selectedDishes.remove(name);
    notifyListeners();
  }

  void onDishNameChanged(String value) {
    _suggestTimer?.cancel();
    if (value.length < 3) {
      suggestedDishName = '';
      notifyListeners();
      return;
    }

    _suggestTimer = Timer(const Duration(milliseconds: 600), () async {
      final res = await _ai.suggestDishName(value);
      if (res is Success<String>) {
        suggestedDishName = res.data;
        notifyListeners();
      }
    });
  }

  Future<bool> submit(
      {required int stoveCount, required int servingCount}) async {
    if (isSubmitting) return false;
    if (selectedDishes.isEmpty) {
      errorMessage = 'Please add at least one dish.';
      notifyListeners();
      return false;
    }
    if (selectedDishes.length > maxDishes) {
      errorMessage = 'You can add up to $maxDishes dishes.';
      notifyListeners();
      return false;
    }
    if (stoveCount < 1 || stoveCount > maxStoves) {
      errorMessage = 'Choose between 1 and $maxStoves stoves.';
      notifyListeners();
      return false;
    }

    isSubmitting = true;
    errorMessage = null;
    notifyListeners();

    // Persist for future use
    stoves = stoveCount;
    servings = servingCount;
    await _storage.saveSettings(stoves: stoves, servings: servings);

    generated = [];
    final userId = await _storage.userId;
    // One backend call for the whole meal: the backend reuses any dish already in the DB and
    // asks Gemini only for the missing ones, returning a standalone (never combined) recipe each.
    final result = await _service.generateRecipesBatch(
      dishNames: List<String>.from(selectedDishes),
      userId: userId,
    );
    switch (result) {
      case Success(data: final recipes):
        generated = recipes;
        notifyListeners();
        break;
      case Failure(message: final message):
        isSubmitting = false;
        errorMessage = selectedDishes.length == 1
            ? message
            : 'Could not generate the recipes: $message';
        notifyListeners();
        return false;
    }

    isSubmitting = false;
    notifyListeners();
    return true;
  }
}

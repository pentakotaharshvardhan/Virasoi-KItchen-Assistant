import 'dart:async';
import 'package:flutter/material.dart';
import '../core/utils/result.dart';
import '../core/utils/secure_storage.dart';
import '../models/recipe_model.dart';
import '../services/recipe_service.dart';
import '../services/ai_service.dart';

class CreateRecipeViewModel extends ChangeNotifier {
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
    stoves = await _storage.stoveCount;
    servings = await _storage.servingCount;
    notifyListeners();
  }

  void addDish(String name) {
    final clean = name.trim();
    if (clean.isNotEmpty && !selectedDishes.contains(clean)) {
      selectedDishes.add(clean);
      suggestedDishName = '';
      notifyListeners();
    }
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

    isSubmitting = true;
    errorMessage = null;
    notifyListeners();

    // Persist for future use
    stoves = stoveCount;
    servings = servingCount;
    await _storage.saveSettings(stoves: stoves, servings: servings);

    generated = [];
    final userId = await _storage.userId;
    for (final dishName in selectedDishes) {
      final result =
          await _service.generateRecipe(dishName: dishName, userId: userId);
      switch (result) {
        case Success(data: final recipe):
          generated.add(recipe);
          notifyListeners();
          break;
        case Failure(message: final message):
          isSubmitting = false;
          errorMessage = selectedDishes.length == 1
              ? message
              : 'Could not generate "$dishName": $message';
          notifyListeners();
          return false;
      }
    }

    isSubmitting = false;
    notifyListeners();
    return true;
  }
}

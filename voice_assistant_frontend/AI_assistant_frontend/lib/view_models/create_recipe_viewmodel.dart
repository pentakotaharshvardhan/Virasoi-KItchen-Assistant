import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/utils/result.dart';
import '../core/utils/secure_storage.dart';
import '../models/recipe_model.dart';
import '../services/recipe_service.dart';

class CreateRecipeViewModel extends ChangeNotifier {
  static const int maxStoves = 4;
  static const int maxDishes = 4;

  CreateRecipeViewModel({
    RecipeService? service,
    SecureStorage? storage,
  })  : _service = service ?? RecipeService(),
        _storage = storage ?? SecureStorage.instance;

  final RecipeService _service;
  final SecureStorage _storage;

  bool isSubmitting = false;
  String? errorMessage;
  List<RecipeModel> generated = [];
  List<RecipeModel> suggestedRecipes = [];

  List<String> selectedDishes = [];
  int stoves = 1;
  int servings = 2;

  Timer? _suggestTimer;
  List<RecipeModel> _userRecipes = [];

  String get suggestedDishName =>
      suggestedRecipes.isEmpty ? '' : suggestedRecipes.first.dishName;

  Future<void> init() async {
    final storedStoveCount = await _storage.stoveCount;
    stoves = storedStoveCount < 1
        ? 1
        : storedStoveCount > maxStoves
            ? maxStoves
            : storedStoveCount;
    servings = await _storage.servingCount;
    final userId = await _storage.userId;
    if (userId != null && userId.isNotEmpty) {
      final result = await _service.getRecipesByUserId(userId);
      if (result case Success(data: final recipes)) {
        _userRecipes = recipes;
      }
    }
    notifyListeners();
  }

  void beginDraft({String? initialDishName}) {
    _suggestTimer?.cancel();
    selectedDishes = [];
    suggestedRecipes = [];
    generated = [];
    errorMessage = null;
    final initial = initialDishName?.trim();
    if (initial != null && initial.isNotEmpty) {
      addDish(initial);
    } else {
      notifyListeners();
    }
  }

  bool addDish(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return false;
    if (selectedDishes.any((dish) => dish.toLowerCase() == clean.toLowerCase()))
      return true;
    if (selectedDishes.length >= maxDishes) {
      _suggestTimer?.cancel();
      suggestedRecipes = [];
      errorMessage = 'You can add up to $maxDishes dishes.';
      notifyListeners();
      return false;
    }

    selectedDishes.add(clean);
    suggestedRecipes = [];
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
    suggestedRecipes = [];
    notifyListeners();
    final query = _normalizeDish(value);
    if (query.length < 3) {
      return;
    }

    _suggestTimer = Timer(const Duration(milliseconds: 250), () {
      final matches = _userRecipes
          .map((recipe) => (
                recipe: recipe,
                distance: _bestNameDistance(query, recipe.dishName),
              ))
          .where((match) => match.distance <= math.max(1, query.length ~/ 4))
          .toList()
        ..sort((a, b) {
          final score = a.distance.compareTo(b.distance);
          return score != 0
              ? score
              : a.recipe.dishName
                  .toLowerCase()
                  .compareTo(b.recipe.dishName.toLowerCase());
        });
      suggestedRecipes =
          matches.take(5).map((match) => match.recipe).toList(growable: false);
      notifyListeners();
    });
  }

  void selectSuggestedRecipe(RecipeModel recipe) {
    addDish(recipe.dishName);
  }

  static String _normalizeDish(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static int _bestNameDistance(String query, String dishName) {
    final normalizedDish = _normalizeDish(dishName);
    if (normalizedDish.contains(query)) return 0;
    final words = dishName
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((word) => word.isNotEmpty);
    var best = _editDistance(query, normalizedDish);
    for (final word in words) {
      best = math.min(best, _editDistance(query, word));
    }
    return best;
  }

  static int _editDistance(String left, String right) {
    if (left.isEmpty) return right.length;
    if (right.isEmpty) return left.length;
    var previous = List<int>.generate(right.length + 1, (i) => i);
    for (var i = 1; i <= left.length; i++) {
      final current = List<int>.filled(right.length + 1, 0)..[0] = i;
      for (var j = 1; j <= right.length; j++) {
        final substitutionCost = left[i - 1] == right[j - 1] ? 0 : 1;
        current[j] = math.min(
          math.min(current[j - 1] + 1, previous[j] + 1),
          previous[j - 1] + substitutionCost,
        );
      }
      previous = current;
    }
    return previous.last;
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

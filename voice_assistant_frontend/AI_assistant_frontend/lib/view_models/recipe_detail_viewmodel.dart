import 'package:flutter/material.dart';
import '../core/utils/result.dart';
import '../models/recipe_model.dart';
import '../services/recipe_service.dart';
import '../services/timer_service.dart';

enum DetailStatus { loading, loaded, error }

class RecipeDetailViewModel extends ChangeNotifier {
  RecipeDetailViewModel({RecipeService? service}) : _service = service ?? RecipeService();

  final RecipeService _service;

  DetailStatus status = DetailStatus.loading;
  String? errorMessage;
  RecipeModel? recipe;

  Future<void> load(String recipeId) async {
    status = DetailStatus.loading;
    notifyListeners();
    final result = await _service.getRecipeById(recipeId);
    switch (result) {
      case Success(data: final r):
        recipe = r;
        status = DetailStatus.loaded;
        break;
      case Failure(message: final m):
        errorMessage = m;
        status = DetailStatus.error;
        break;
    }
    notifyListeners();
  }

  void startStepTimer(int stepIndex) {
    final step = recipe?.steps[stepIndex];
    if (step == null || step.baseTimerSeconds <= 0) return;
    TimerService.instance.startTimer(
      id: '${recipe!.id}_step_$stepIndex',
      label: 'Step ${step.stepNumber}',
      seconds: step.baseTimerSeconds,
    );
  }
}

import 'package:ai_assistant_frontend/models/ingredient_model.dart';
import 'package:ai_assistant_frontend/models/recipe_model.dart';
import 'package:ai_assistant_frontend/models/recipe_step_model.dart';

/// JSON builders mirroring the shapes the backend is expected to return.
/// Keeping them in one place makes the tests readable and easy to update
/// when the real Swagger contract is confirmed.

Map<String, dynamic> ingredientJson({
  String id = 'ing-1',
  String name = 'Onion',
  num quantityPerServe = 2,
  String unit = 'pcs',
  String? imageUrl,
}) =>
    {
      'id': id,
      'name': name,
      'quantityPerServe': quantityPerServe,
      'unit': unit,
      if (imageUrl != null) 'imageUrl': imageUrl,
    };

Map<String, dynamic> stepJson({
  String id = 'step-1',
  int stepNumber = 1,
  String instruction = 'Chop the onions',
  String stepType = 'prep',
  bool requiresTimer = false,
  int baseTimerSeconds = 0,
  bool scalesWithServes = false,
  String? ingredientName,
}) =>
    {
      'id': id,
      'stepNumber': stepNumber,
      'instruction': instruction,
      'stepType': stepType,
      'requiresTimer': requiresTimer,
      'baseTimerSeconds': baseTimerSeconds,
      'scalesWithServes': scalesWithServes,
      if (ingredientName != null) 'ingredientName': ingredientName,
    };

Map<String, dynamic> recipeJson({
  String id = 'recipe-1',
  String dishName = 'Paneer Butter Masala',
  String description = 'A rich and creamy North Indian curry.',
  int baseServes = 2,
  String source = 'ai',
  String? createdBy,
  String createdAt = '2026-01-10T10:00:00.000Z',
  List<Map<String, dynamic>>? ingredients,
  List<Map<String, dynamic>>? steps,
}) =>
    {
      'id': id,
      'dishName': dishName,
      'description': description,
      'baseServes': baseServes,
      'source': source,
      if (createdBy != null) 'createdBy': createdBy,
      'createdAt': createdAt,
      'ingredients': ingredients ?? [ingredientJson()],
      'steps': steps ?? [stepJson()],
    };

RecipeModel sampleRecipe({
  String id = 'recipe-1',
  String dishName = 'Paneer Butter Masala',
  String source = 'ai',
  DateTime? createdAt,
  List<Map<String, dynamic>>? ingredients,
  List<Map<String, dynamic>>? steps,
}) {
  final json = recipeJson(
    id: id,
    dishName: dishName,
    source: source,
    ingredients: ingredients,
    steps: steps,
  );
  if (createdAt != null) json['createdAt'] = createdAt.toIso8601String();
  return RecipeModel.fromJson(json);
}

List<RecipeModel> sampleRecipes() => [
      sampleRecipe(
        id: 'r-1',
        dishName: 'Paneer Butter Masala',
        source: 'ai',
        createdAt: DateTime.utc(2026, 1, 3),
        steps: [stepJson(baseTimerSeconds: 600)],
      ),
      sampleRecipe(
        id: 'r-2',
        dishName: 'Aloo Gobi',
        source: 'user',
        createdAt: DateTime.utc(2026, 1, 1),
        steps: [stepJson(baseTimerSeconds: 300)],
      ),
      sampleRecipe(
        id: 'r-3',
        dishName: 'Chicken Biryani',
        source: 'ai',
        createdAt: DateTime.utc(2026, 1, 2),
        steps: [stepJson(baseTimerSeconds: 900)],
      ),
    ];

RecipeModel recipeWithIngredients(
  List<IngredientModel> ingredients, {
  String id = 'recipe-ing',
  String dishName = 'Test Dish',
}) =>
    RecipeModel(
      id: id,
      dishName: dishName,
      description: 'desc',
      baseServes: 2,
      source: 'ai',
      createdAt: DateTime.utc(2026, 1, 1),
      ingredients: ingredients,
      steps: const <RecipeStepModel>[],
    );

import 'ingredient_model.dart';
import 'recipe_step_model.dart';

enum RecipeSource { user, ai }

class RecipeModel {
  final String id;
  final String dishName;
  final String? dishNameNormalized;
  final String description;
  final int baseServes;
  final String source;
  final String? createdBy;
  final DateTime createdAt;
  final List<IngredientModel> ingredients;
  final List<RecipeStepModel> steps;

  RecipeModel({
    required this.id,
    required this.dishName,
    this.dishNameNormalized,
    required this.description,
    required this.baseServes,
    required this.source,
    this.createdBy,
    required this.createdAt,
    this.ingredients = const [],
    this.steps = const [],
  });

  factory RecipeModel.fromJson(Map<String, dynamic> json) => RecipeModel(
        id: (json['id'] ?? '').toString(),
        dishName: (json['dishName'] ?? 'Untitled recipe').toString(),
        dishNameNormalized: json['dishNameNormalized']?.toString(),
        description: (json['description'] ?? '').toString(),
        baseServes: (json['baseServes'] ?? 1) as int,
        source: (json['source'] ?? 'user').toString(),
        createdBy: json['createdBy']?.toString(),
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
        ingredients: (json['ingredients'] as List<dynamic>? ?? [])
            .map((e) => IngredientModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        steps: (json['steps'] as List<dynamic>? ?? [])
            .map((e) => RecipeStepModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  // Helper for UI title
  String get title => dishName;
  
  // Helper for UI total time - sum of step timers
  int get totalTimeMinutes {
    final totalSeconds = steps.fold(0, (sum, step) => sum + step.baseTimerSeconds);
    return (totalSeconds / 60).ceil();
  }

  // Cover image URL is not in the schema, but we can keep it as an optional field if needed for UI
  String? get coverImageUrl => null;
}

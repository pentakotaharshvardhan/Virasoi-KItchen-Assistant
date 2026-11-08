import '../core/constants/api_constants.dart';
import '../core/network/api_client.dart';
import '../core/utils/result.dart';
import '../models/recipe_model.dart';

class IngredientService {
  IngredientService({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  Future<Result<RecipeModel>> getRecipeWithIngredients(String recipeId) async {
    final res = await _api.get(ApiConstants.recipeById(recipeId));
    return switch (res) {
      Success(data: final data) => Success(RecipeModel.fromJson(data as Map<String, dynamic>)),
      Failure(message: final m) => Failure(m),
    };
  }

  /// Loads every recipe of a multi-dish meal so the items screen can merge their ingredients.
  /// Fails fast with the first error so a broken id never yields a partial shopping list.
  Future<Result<List<RecipeModel>>> getRecipesWithIngredients(List<String> recipeIds) async {
    final recipes = <RecipeModel>[];
    for (final id in recipeIds) {
      final res = await getRecipeWithIngredients(id);
      switch (res) {
        case Success(data: final recipe):
          recipes.add(recipe);
        case Failure(message: final m):
          return Failure(m);
      }
    }
    return Success(recipes);
  }
}

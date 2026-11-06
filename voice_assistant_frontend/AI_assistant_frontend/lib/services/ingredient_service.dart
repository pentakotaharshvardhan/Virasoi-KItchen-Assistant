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
}

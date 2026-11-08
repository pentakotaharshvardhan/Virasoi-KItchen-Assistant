import '../core/constants/api_constants.dart';
import '../core/network/api_client.dart';
import '../core/utils/result.dart';
import '../models/recipe_model.dart';

enum RecipeSortOption { timeAsc, timeDesc, alphabetical, totalTime }

class RecipeService {
  RecipeService({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  Future<Result<List<RecipeModel>>> getRecipes(
      {String? search, RecipeSortOption? sort}) async {
    final query = <String, dynamic>{};
    if (search != null && search.isNotEmpty) query['search'] = search;
    if (sort != null) query['sort'] = _sortParam(sort);

    final res = await _api.get(ApiConstants.recipes, query: query);
    return switch (res) {
      Success(data: final data) => Success(
          ((data is List ? data : data['items'] ?? []) as List)
              .map((e) => RecipeModel.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      Failure(message: final m) => Failure(m),
    };
  }

  Future<Result<List<RecipeModel>>> getRecipesByUserId(String userId) async {
    final res = await _api.get(ApiConstants.recipesByUser(userId));
    return switch (res) {
      Success(data: final data) => Success(
          ((data is List ? data : data['items'] ?? []) as List)
              .map((e) => RecipeModel.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      Failure(message: final m) => Failure(m),
    };
  }

  Future<Result<RecipeModel>> getRecipeById(String id) async {
    final res = await _api.get(ApiConstants.recipeById(id));
    return switch (res) {
      Success(data: final data) =>
        Success(RecipeModel.fromJson(data as Map<String, dynamic>)),
      Failure(message: final m) => Failure(m),
    };
  }

  Future<Result<RecipeModel>> generateRecipe({
    required String dishName,
    String? userId,
  }) async {
    final res = await _api.post(ApiConstants.generateRecipe, body: {
      'dishName': dishName,
      if (userId != null && userId.isNotEmpty) 'userId': userId,
    });
    return switch (res) {
      Success(data: final data) =>
        Success(RecipeModel.fromJson(data as Map<String, dynamic>)),
      Failure(message: final m) => Failure(m),
    };
  }

  /// Generates every dish of a multi-dish meal in ONE backend call. The backend reuses
  /// whatever is already in the DB and asks the AI only for the missing dishes, returning
  /// one standalone recipe per dish (never a combined "combo" recipe).
  Future<Result<List<RecipeModel>>> generateRecipesBatch({
    required List<String> dishNames,
    String? userId,
  }) async {
    final res = await _api.post(ApiConstants.generateRecipeBatch, body: {
      'dishNames': dishNames,
      if (userId != null && userId.isNotEmpty) 'userId': userId,
    });
    return switch (res) {
      Success(data: final data) => Success(
          ((data is List ? data : data['items'] ?? []) as List)
              .map((e) => RecipeModel.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      Failure(message: final m) => Failure(m),
    };
  }

  Future<Result<RecipeModel>> findOrGenerateRecipe({
    required String dishName,
  }) async {
    final res = await _api.post(ApiConstants.findOrGenerateRecipe, body: {
      'dishName': dishName,
    });
    return switch (res) {
      Success(data: final data) =>
        Success(RecipeModel.fromJson(data as Map<String, dynamic>)),
      Failure(message: final m) => Failure(m),
    };
  }

  String _sortParam(RecipeSortOption s) => switch (s) {
        RecipeSortOption.timeAsc => 'time_asc',
        RecipeSortOption.timeDesc => 'time_desc',
        RecipeSortOption.alphabetical => 'alphabetical',
        RecipeSortOption.totalTime => 'total_time',
      };
}

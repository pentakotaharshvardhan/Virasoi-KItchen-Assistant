import 'dart:convert';

import 'package:ai_assistant_frontend/core/network/api_client.dart';
import 'package:ai_assistant_frontend/core/utils/result.dart';
import 'package:ai_assistant_frontend/models/recipe_model.dart';
import 'package:ai_assistant_frontend/services/recipe_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import '../helpers/fakes.dart';
import '../helpers/fixtures.dart';

void main() {
  test('getRecipes parses a bare JSON array', () async {
    final api = ApiClient.withClient(MockClient((request) async {
      expect(request.url.path, '/api/recipes');
      return jsonResponse([recipeJson(id: 'r-1'), recipeJson(id: 'r-2')]);
    }));

    final result = await RecipeService(api: api).getRecipes();

    final recipes = (result as Success<List<RecipeModel>>).data;
    expect(recipes.map((r) => r.id), ['r-1', 'r-2']);
  });

  test('getRecipesByUserId hits the user recipes path', () async {
    late Uri requested;
    final api = ApiClient.withClient(MockClient((request) async {
      requested = request.url;
      return jsonResponse([recipeJson(id: 'r-7')]);
    }));

    final result = await RecipeService(api: api).getRecipesByUserId('user-42');

    expect(requested.path, '/api/recipes/user/user-42');
    expect((result as Success<List<RecipeModel>>).data.single.id, 'r-7');
  });

  test('getRecipes also accepts a paginated items wrapper', () async {
    final api = ApiClient.withClient(MockClient(
      (_) async => jsonResponse({
        'items': [recipeJson(id: 'r-9')],
        'total': 1,
      }),
    ));

    final result = await RecipeService(api: api).getRecipes();

    expect((result as Success<List<RecipeModel>>).data.single.id, 'r-9');
  });

  test('getRecipes forwards search and sort query parameters', () async {
    late Uri requested;
    final api = ApiClient.withClient(MockClient((request) async {
      requested = request.url;
      return jsonResponse([]);
    }));

    await RecipeService(api: api).getRecipes(
      search: 'biryani',
      sort: RecipeSortOption.totalTime,
    );

    expect(requested.queryParameters['search'], 'biryani');
    expect(requested.queryParameters['sort'], 'total_time');
  });

  test('every sort option maps to its backend value', () async {
    const expected = {
      RecipeSortOption.timeAsc: 'time_asc',
      RecipeSortOption.timeDesc: 'time_desc',
      RecipeSortOption.alphabetical: 'alphabetical',
      RecipeSortOption.totalTime: 'total_time',
    };

    for (final entry in expected.entries) {
      late Uri requested;
      final api = ApiClient.withClient(MockClient((request) async {
        requested = request.url;
        return jsonResponse([]);
      }));

      await RecipeService(api: api).getRecipes(sort: entry.key);

      expect(requested.queryParameters['sort'], entry.value);
    }
  });

  test('getRecipeById hits the nested recipe path', () async {
    late Uri requested;
    final api = ApiClient.withClient(MockClient((request) async {
      requested = request.url;
      return jsonResponse(recipeJson(id: 'abc'));
    }));

    final result = await RecipeService(api: api).getRecipeById('abc');

    expect(requested.path, '/api/recipes/abc');
    expect((result as Success<RecipeModel>).data.id, 'abc');
  });

  test('generateRecipe posts the dishName', () async {
    late Map<String, dynamic> body;
    final api = ApiClient.withClient(MockClient((request) async {
      expect(request.url.path, '/api/recipes/generate');
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return jsonResponse(recipeJson(dishName: 'Dal Makhani'));
    }));

    final result =
        await RecipeService(api: api).generateRecipe(dishName: 'Dal Makhani');

    expect(body, {'dishName': 'Dal Makhani'});
    expect((result as Success<RecipeModel>).data.dishName, 'Dal Makhani');
  });

  test('generateRecipe includes the userId when one is provided', () async {
    late Map<String, dynamic> body;
    final api = ApiClient.withClient(MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return jsonResponse(recipeJson(dishName: 'Dal Makhani'));
    }));

    await RecipeService(api: api)
        .generateRecipe(dishName: 'Dal Makhani', userId: 'user-42');

    expect(body, {'dishName': 'Dal Makhani', 'userId': 'user-42'});
  });

  test('findOrGenerateRecipe posts to its own endpoint', () async {
    late Uri requested;
    final api = ApiClient.withClient(MockClient((request) async {
      requested = request.url;
      return jsonResponse(recipeJson());
    }));

    await RecipeService(api: api).findOrGenerateRecipe(dishName: 'Idli');

    expect(requested.path, '/api/recipes/find-or-generate');
  });

  test('propagates failures from the backend', () async {
    final api = ApiClient.withClient(
      MockClient((_) async =>
          jsonResponse({'message': 'Recipe not found'}, status: 404)),
    );

    final result = await RecipeService(api: api).getRecipeById('missing');

    expect(result, isA<Failure<RecipeModel>>());
    expect((result as Failure).message, 'Recipe not found');
  });
}

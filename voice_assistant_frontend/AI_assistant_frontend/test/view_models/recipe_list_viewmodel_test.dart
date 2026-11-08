import 'package:ai_assistant_frontend/core/utils/result.dart';
import 'package:ai_assistant_frontend/core/utils/secure_storage.dart';
import 'package:ai_assistant_frontend/services/recipe_service.dart';
import 'package:ai_assistant_frontend/view_models/recipe_list_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';
import '../helpers/fixtures.dart';

void main() {
  late FakeRecipeService service;
  late SecureStorage storage;
  late RecipeListViewModel vm;

  setUp(() async {
    service = FakeRecipeService();
    storage = SecureStorage.inMemory();
    await storage.saveSession(accessToken: 'jwt', userId: 'user-42');
    vm = RecipeListViewModel(service: service, storage: storage);
  });

  test('load exposes the recipes and reports loaded', () async {
    await vm.load();

    expect(vm.status, ListStatus.loaded);
    expect(vm.visible.length, 3);
    expect(vm.errorMessage, isNull);
    expect(service.listByUserCalls, 1);
    expect(service.listCalls, 0);
    expect(service.lastUserId, 'user-42');
  });

  test('load without a stored user id skips the API and shows nothing',
      () async {
    await storage.clear();
    vm = RecipeListViewModel(service: service, storage: storage);

    await vm.load();

    expect(vm.status, ListStatus.loaded);
    expect(vm.visible, isEmpty);
    expect(service.listByUserCalls, 0);
    expect(service.listCalls, 0);
  });

  test('load failure switches to error and keeps the message', () async {
    service.listResult = const Failure('Server exploded');

    await vm.load();

    expect(vm.status, ListStatus.error);
    expect(vm.errorMessage, 'Server exploded');
  });

  test('an empty result is loaded but visible is empty', () async {
    service.listResult = const Success([]);

    await vm.load();

    expect(vm.status, ListStatus.loaded);
    expect(vm.visible, isEmpty);
  });

  test('default sort is oldest first', () async {
    await vm.load();

    expect(vm.sort, RecipeSortOption.timeAsc);
    expect(vm.visible.map((r) => r.id), ['r-2', 'r-3', 'r-1']);
  });

  test('newest first reverses the creation order', () async {
    await vm.load();

    vm.changeSort(RecipeSortOption.timeDesc);

    expect(vm.visible.map((r) => r.id), ['r-1', 'r-3', 'r-2']);
  });

  test('alphabetical sort ignores case', () async {
    await vm.load();

    vm.changeSort(RecipeSortOption.alphabetical);

    expect(vm.visible.map((r) => r.dishName), [
      'Aloo Gobi',
      'Chicken Biryani',
      'Paneer Butter Masala',
    ]);
  });

  test('reverse alphabetical sort is supported', () async {
    await vm.load();

    vm.changeSort(RecipeSortOption.alphabeticalDesc);

    expect(vm.visible.map((r) => r.dishName), [
      'Paneer Butter Masala',
      'Chicken Biryani',
      'Aloo Gobi',
    ]);
  });

  test('origin filter separates ancestor and AI recipes', () async {
    service.listResult = Success([
      sampleRecipe(id: 'ancestor', dishName: 'Family Dal', source: 'ANCESTOR'),
      sampleRecipe(id: 'ai', dishName: 'AI Dal', source: 'AI_GENERATED'),
    ]);
    await vm.load();

    vm.changeOriginFilter(RecipeOriginFilter.ancestor);
    expect(vm.visible.map((r) => r.id), ['ancestor']);

    vm.changeOriginFilter(RecipeOriginFilter.aiGenerated);
    expect(vm.visible.map((r) => r.id), ['ai']);
  });

  test('total time sort puts the quickest recipe first', () async {
    await vm.load();

    vm.changeSort(RecipeSortOption.totalTime);

    expect(vm.visible.map((r) => r.id), ['r-2', 'r-1', 'r-3']);
  });

  test('search filters recipe titles case-insensitively', () async {
    await vm.load();

    vm.search('PANEER');

    expect(vm.visible.single.dishName, 'Paneer Butter Masala');
  });

  test('search with no matches yields an empty list', () async {
    await vm.load();

    vm.search('sushi');

    expect(vm.visible, isEmpty);
  });

  test('clearing the search restores every recipe', () async {
    await vm.load();
    vm.search('paneer');

    vm.search('');

    expect(vm.visible.length, 3);
  });

  test('search and sort compose', () async {
    await vm.load();
    vm.search('a');

    vm.changeSort(RecipeSortOption.alphabetical);

    expect(vm.visible.map((r) => r.dishName), [
      'Aloo Gobi',
      'Chicken Biryani',
      'Paneer Butter Masala',
    ]);
  });

  test('changeSort and search notify listeners', () async {
    await vm.load();
    var notifications = 0;
    vm.addListener(() => notifications++);

    vm.search('paneer');
    vm.changeSort(RecipeSortOption.alphabetical);

    expect(notifications, greaterThanOrEqualTo(2));
  });
}

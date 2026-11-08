import 'package:ai_assistant_frontend/core/utils/result.dart';
import 'package:ai_assistant_frontend/core/utils/secure_storage.dart';
import 'package:ai_assistant_frontend/view_models/create_recipe_viewmodel.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';
import '../helpers/fixtures.dart';

void main() {
  late FakeRecipeService service;
  late FakeAiService ai;
  late SecureStorage storage;

  setUp(() {
    service = FakeRecipeService();
    ai = FakeAiService();
    storage = SecureStorage.inMemory();
  });

  CreateRecipeViewModel buildViewModel() => CreateRecipeViewModel(
        service: service,
        aiService: ai,
        storage: storage,
      );

  test('init loads the persisted kitchen settings', () async {
    await storage.saveSettings(stoves: 3, servings: 5);
    final vm = buildViewModel();

    await vm.init();

    expect(vm.stoves, 3);
    expect(vm.servings, 5);
  });

  test('init clamps a saved stove count to the maximum', () async {
    await storage.saveSettings(stoves: 5, servings: 2);
    final vm = buildViewModel();

    await vm.init();

    expect(vm.stoves, CreateRecipeViewModel.maxStoves);
  });

  test('init falls back to defaults when nothing is stored', () async {
    final vm = buildViewModel();

    await vm.init();

    expect(vm.stoves, 1);
    expect(vm.servings, 2);
  });

  test('addDish trims, ignores blanks and de-duplicates', () {
    final vm = buildViewModel();

    vm.addDish('  Paneer Tikka  ');
    vm.addDish('');
    vm.addDish('   ');
    vm.addDish('Paneer Tikka');
    vm.addDish('Dal Makhani');

    expect(vm.selectedDishes, ['Paneer Tikka', 'Dal Makhani']);
  });

  test('addDish clears any previous suggestion', () {
    final vm = buildViewModel();
    vm.suggestedDishName = 'Stale suggestion';

    vm.addDish('Dal');

    expect(vm.suggestedDishName, '');
  });

  test('addDish rejects a fifth dish', () {
    final vm = buildViewModel();
    for (var i = 1; i <= CreateRecipeViewModel.maxDishes; i++) {
      expect(vm.addDish('Dish $i'), isTrue);
    }

    expect(vm.addDish('Dish 5'), isFalse);
    expect(vm.selectedDishes, hasLength(CreateRecipeViewModel.maxDishes));
    expect(vm.errorMessage, 'You can add up to 4 dishes.');
  });

  test('removeDish removes only the requested chip', () {
    final vm = buildViewModel();
    vm.addDish('A');
    vm.addDish('B');

    vm.removeDish('A');

    expect(vm.selectedDishes, ['B']);
  });

  test('short input clears the suggestion without calling the AI', () {
    final vm = buildViewModel();
    vm.suggestedDishName = 'Old';

    vm.onDishNameChanged('pa');

    expect(vm.suggestedDishName, '');
    expect(ai.suggestions, isEmpty);
  });

  test('debounced suggestion waits 600ms before calling the AI', () {
    fakeAsync((async) {
      final vm = buildViewModel();
      ai.suggestionResult = const Success('Paneer Tikka');

      vm.onDishNameChanged('pan');
      async.elapse(const Duration(milliseconds: 599));
      expect(ai.suggestions, isEmpty);

      async.elapse(const Duration(milliseconds: 2));
      async.flushMicrotasks();

      expect(ai.suggestions, ['pan']);
      expect(vm.suggestedDishName, 'Paneer Tikka');
    });
  });

  test('typing again resets the debounce window', () {
    fakeAsync((async) {
      final vm = buildViewModel();
      ai.suggestionResult = const Success('Paneer Tikka');

      vm.onDishNameChanged('pan');
      async.elapse(const Duration(milliseconds: 400));
      vm.onDishNameChanged('paneer');
      async.elapse(const Duration(milliseconds: 400));

      expect(ai.suggestions, isEmpty);

      async.elapse(const Duration(milliseconds: 250));
      async.flushMicrotasks();

      expect(ai.suggestions, ['paneer']);
    });
  });

  test('submit without dishes fails with a helpful message', () async {
    final vm = buildViewModel();

    final ok = await vm.submit(stoveCount: 1, servingCount: 2);

    expect(ok, isFalse);
    expect(vm.errorMessage, 'Please add at least one dish.');
    expect(service.batchCalls, 0);
  });

  test('submit rejects more than four stoves before generating recipes',
      () async {
    final vm = buildViewModel()..addDish('Paneer');

    final ok = await vm.submit(stoveCount: 5, servingCount: 2);

    expect(ok, isFalse);
    expect(vm.errorMessage, 'Choose between 1 and 4 stoves.');
    expect(service.batchCalls, 0);
  });

  test(
      'submit generates the whole meal in one batch call and stores the settings',
      () async {
    await storage.saveSession(accessToken: 'jwt', userId: 'user-42');
    service.batchResult = Success([
      sampleRecipe(id: 'r-1', dishName: 'Paneer'),
      sampleRecipe(id: 'r-2', dishName: 'Naan'),
    ]);
    final vm = buildViewModel();
    vm.addDish('Paneer');
    vm.addDish('Naan');

    final future = vm.submit(stoveCount: 2, servingCount: 4);
    expect(vm.isSubmitting, isTrue);

    final ok = await future;

    expect(ok, isTrue);
    expect(vm.isSubmitting, isFalse);
    expect(service.batchCalls, 1, reason: 'one request for the whole meal');
    expect(service.batchDishNames, [
      ['Paneer', 'Naan']
    ]);
    expect(service.batchUserIds, ['user-42']);
    expect(vm.generated, hasLength(2));
    expect(vm.generated.map((r) => r.dishName), ['Paneer', 'Naan']);
    expect(await storage.stoveCount, 2);
    expect(await storage.servingCount, 4);
  });

  test('submit failure restores the submitting flag and records the error',
      () async {
    service.batchResult = const Failure('AI quota exhausted');
    final vm = buildViewModel();
    vm.addDish('Paneer');

    final ok = await vm.submit(stoveCount: 1, servingCount: 2);

    expect(ok, isFalse);
    expect(vm.isSubmitting, isFalse);
    expect(vm.errorMessage, 'AI quota exhausted');
    expect(vm.generated, isEmpty);
  });

  test('submit failure names the batch when several dishes were requested',
      () async {
    service.batchResult = const Failure('AI quota exhausted');
    final vm = buildViewModel();
    vm.addDish('Paneer');
    vm.addDish('Naan');

    final ok = await vm.submit(stoveCount: 1, servingCount: 2);

    expect(ok, isFalse);
    expect(service.batchDishNames, [
      ['Paneer', 'Naan']
    ]);
    expect(
        vm.errorMessage, 'Could not generate the recipes: AI quota exhausted');
    expect(vm.generated, isEmpty);
    expect(vm.isSubmitting, isFalse);
  });

  test('submit clears a previous error on retry', () async {
    service.batchResult = const Failure('temporary');
    final vm = buildViewModel();
    vm.addDish('Paneer');
    await vm.submit(stoveCount: 1, servingCount: 2);

    service.batchResult = Success([sampleRecipe()]);
    final ok = await vm.submit(stoveCount: 1, servingCount: 2);

    expect(ok, isTrue);
    expect(vm.errorMessage, isNull);
    expect(vm.generated.single.dishName, 'Paneer Butter Masala');
  });
}

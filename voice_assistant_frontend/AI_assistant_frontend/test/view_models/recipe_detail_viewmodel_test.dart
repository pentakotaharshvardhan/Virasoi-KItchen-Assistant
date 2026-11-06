import 'package:ai_assistant_frontend/core/utils/result.dart';
import 'package:ai_assistant_frontend/services/timer_service.dart';
import 'package:ai_assistant_frontend/view_models/recipe_detail_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';
import '../helpers/fixtures.dart';

void main() {
  late FakeRecipeService service;
  late RecipeDetailViewModel vm;

  setUp(() {
    TimerService.instance.resetForTest();
    service = FakeRecipeService();
    vm = RecipeDetailViewModel(service: service);
  });

  tearDown(() => TimerService.instance.resetForTest());

  test('load exposes the recipe and reports loaded', () async {
    service.byIdResult = Success(sampleRecipe(id: 'abc'));

    await vm.load('abc');

    expect(vm.status, DetailStatus.loaded);
    expect(vm.recipe?.id, 'abc');
    expect(service.lastRequestedId, 'abc');
  });

  test('load failure reports the error state', () async {
    service.byIdResult = const Failure('Not found');

    await vm.load('missing');

    expect(vm.status, DetailStatus.error);
    expect(vm.errorMessage, 'Not found');
    expect(vm.recipe, isNull);
  });

  test('startStepTimer starts a timer with the step duration', () async {
    service.byIdResult = Success(sampleRecipe(
      id: 'r-9',
      steps: [stepJson(stepNumber: 2, baseTimerSeconds: 120)],
    ));
    await vm.load('r-9');

    vm.startStepTimer(0);

    final timer = TimerService.instance.activeTimers.single;
    expect(timer.id, 'r-9_step_0');
    expect(timer.label, 'Step 2');
    expect(timer.totalSeconds, 120);
  });

  test('startStepTimer ignores steps without a timer', () async {
    service.byIdResult = Success(sampleRecipe(
      steps: [stepJson(baseTimerSeconds: 0)],
    ));
    await vm.load('r-1');

    vm.startStepTimer(0);

    expect(TimerService.instance.activeTimers, isEmpty);
  });
}

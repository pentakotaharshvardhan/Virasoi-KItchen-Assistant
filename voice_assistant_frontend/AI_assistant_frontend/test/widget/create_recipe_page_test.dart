import 'package:ai_assistant_frontend/core/routes/app_routes.dart';
import 'package:ai_assistant_frontend/core/utils/result.dart';
import 'package:ai_assistant_frontend/core/utils/secure_storage.dart';
import 'package:ai_assistant_frontend/view_models/create_recipe_viewmodel.dart';
import 'package:ai_assistant_frontend/views/create/create_recipe_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/fakes.dart';
import '../helpers/fixtures.dart';

void main() {
  late FakeRecipeService service;
  late FakeAiService ai;
  late SecureStorage storage;
  late CreateRecipeViewModel vm;

  setUp(() {
    service = FakeRecipeService();
    ai = FakeAiService();
    storage = SecureStorage.inMemory();
    vm = CreateRecipeViewModel(
        service: service, aiService: ai, storage: storage);
  });

  Widget harness() => ChangeNotifierProvider<CreateRecipeViewModel>.value(
        value: vm,
        child: MaterialApp(
          home: const CreateRecipePage(),
          onGenerateRoute: (settings) {
            if (settings.name == AppRoutes.ingredients) {
              return MaterialPageRoute(
                builder: (_) => Scaffold(
                  body: Text('ING:${settings.arguments}'),
                ),
              );
            }
            if (settings.name == AppRoutes.recipeList) {
              return MaterialPageRoute(
                builder: (_) => const Scaffold(body: Text('RECIPE LIST')),
              );
            }
            return null;
          },
        ),
      );

  Future<void> addDish(WidgetTester tester, String name) async {
    await tester.enterText(find.byType(TextFormField), name);
    await tester.tap(find.byIcon(Icons.add_task_rounded));
    await tester.pump();
  }

  testWidgets('renders the create form', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('What are we cooking today?'), findsOneWidget);
    expect(find.text('Generate Recipe'), findsOneWidget);
    expect(find.text('Stoves available (max 4)'), findsOneWidget);
    expect(find.text('Number of servings'), findsOneWidget);
  });

  testWidgets('adding a dish shows a removable chip', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await addDish(tester, 'Paneer Tikka');

    expect(find.text('Paneer Tikka'), findsOneWidget);
    expect(vm.selectedDishes, ['Paneer Tikka']);

    await tester.tap(find.byIcon(Icons.cancel_rounded));
    await tester.pump();

    expect(vm.selectedDishes, isEmpty);
    expect(find.text('Paneer Tikka'), findsNothing);
  });

  testWidgets('duplicate dishes are ignored', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await addDish(tester, 'Paneer');
    await addDish(tester, 'Paneer');

    expect(vm.selectedDishes, ['Paneer']);
  });

  testWidgets('dish selection stops at four', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    for (var i = 1; i <= CreateRecipeViewModel.maxDishes; i++) {
      await addDish(tester, 'Dish $i');
    }
    await addDish(tester, 'Dish 5');

    expect(vm.selectedDishes, hasLength(CreateRecipeViewModel.maxDishes));
    expect(find.text('You can add up to 4 dishes.'), findsOneWidget);
  });

  testWidgets('stove selection cannot exceed four', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byIcon(Icons.add_circle_outline_rounded).at(0));
      await tester.pump();
    }

    expect(find.text('4'), findsOneWidget);
    final stovePlusButton = find.ancestor(
      of: find.byIcon(Icons.add_circle_outline_rounded).at(0),
      matching: find.byType(IconButton),
    );
    expect(
      tester.widget<IconButton>(stovePlusButton).onPressed,
      isNull,
    );
  });

  testWidgets('generating with no dish shows a SnackBar', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Generate Recipe'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.text('Please add at least one dish.'), findsOneWidget);
    expect(service.batchCalls, 0);
  });

  testWidgets('generating navigates to the items screen with the recipe id',
      (tester) async {
    service.batchResult = Success([sampleRecipe(id: 'recipe-1')]);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await addDish(tester, 'Paneer');

    await tester.tap(find.text('Generate Recipe'));
    await tester.pumpAndSettle();

    expect(find.text('ING:[recipe-1]'), findsOneWidget);
  });

  testWidgets(
      'every dish of a multi-dish meal is generated and opened together on the items screen',
      (tester) async {
    service.batchResult = Success([
      sampleRecipe(id: 'recipe-1', dishName: 'Paneer'),
      sampleRecipe(id: 'recipe-2', dishName: 'Naan'),
    ]);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await addDish(tester, 'Paneer');
    await addDish(tester, 'Naan');

    await tester.tap(find.text('Generate Recipes'));
    await tester.pumpAndSettle();

    expect(service.batchDishNames, [
      ['Paneer', 'Naan']
    ]);
    expect(find.text('ING:[recipe-1, recipe-2]'), findsOneWidget);
  });

  testWidgets('kitchen steppers persist through generation', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await addDish(tester, 'Paneer');

    // Two rows: stoves first, then servings.
    await tester.tap(find.byIcon(Icons.add_circle_outline_rounded).at(0));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add_circle_outline_rounded).at(1));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add_circle_outline_rounded).at(1));
    await tester.pump();

    await tester.tap(find.text('Generate Recipe'));
    await tester.pumpAndSettle();

    expect(await storage.stoveCount, 2);
    expect(await storage.servingCount, 4);
  });

  testWidgets('a debounced suggestion can be accepted', (tester) async {
    ai.suggestionResult = const Success('Paneer Tikka');
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'pan');
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Did you mean: Paneer Tikka?'), findsOneWidget);

    await tester.tap(find.text('Did you mean: Paneer Tikka?'));
    await tester.pump();

    await tester.tap(find.text('Generate Recipe'));
    await tester.pumpAndSettle();

    expect(service.batchDishNames, [
      ['Paneer Tikka']
    ]);
  });

  testWidgets('a failed generation keeps the user on the page with an error',
      (tester) async {
    service.batchResult = const Failure('Generation failed');
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await addDish(tester, 'Paneer');

    await tester.tap(find.text('Generate Recipe'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.text('Generation failed'), findsOneWidget);
    expect(find.text('What are we cooking today?'), findsOneWidget);
  });
}

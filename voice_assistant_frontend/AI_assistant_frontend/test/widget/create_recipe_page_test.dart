import 'package:ai_assistant_frontend/core/routes/app_routes.dart';
import 'package:ai_assistant_frontend/core/utils/result.dart';
import 'package:ai_assistant_frontend/core/utils/secure_storage.dart';
import 'package:ai_assistant_frontend/view_models/create_recipe_viewmodel.dart';
import 'package:ai_assistant_frontend/views/create/create_recipe_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/fakes.dart';

void main() {
  late FakeRecipeService service;
  late FakeAiService ai;
  late SecureStorage storage;
  late CreateRecipeViewModel vm;

  setUp(() {
    service = FakeRecipeService();
    ai = FakeAiService();
    storage = SecureStorage.inMemory();
    vm = CreateRecipeViewModel(service: service, aiService: ai, storage: storage);
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
    expect(find.text('Stoves available'), findsOneWidget);
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

  testWidgets('generating with no dish shows a SnackBar', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Generate Recipe'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.text('Please add at least one dish.'), findsOneWidget);
    expect(service.generateCalls, 0);
  });

  testWidgets('generating navigates to ingredients with the new recipe id', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await addDish(tester, 'Paneer');

    await tester.tap(find.text('Generate Recipe'));
    await tester.pumpAndSettle();

    expect(find.text('ING:recipe-1'), findsOneWidget);
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

    expect(service.lastGenerateDish, 'Paneer Tikka');
  });

  testWidgets('a failed generation keeps the user on the page with an error', (tester) async {
    service.generateResult = const Failure('Generation failed');
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

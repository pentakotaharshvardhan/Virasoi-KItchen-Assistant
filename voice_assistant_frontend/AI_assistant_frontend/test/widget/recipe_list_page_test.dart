import 'package:ai_assistant_frontend/core/routes/app_routes.dart';
import 'package:ai_assistant_frontend/core/utils/result.dart';
import 'package:ai_assistant_frontend/core/utils/secure_storage.dart';
import 'package:ai_assistant_frontend/services/recipe_service.dart';
import 'package:ai_assistant_frontend/view_models/recipe_list_viewmodel.dart';
import 'package:ai_assistant_frontend/views/recipe/recipe_list_page.dart';
import 'package:ai_assistant_frontend/widgets/recipe_card_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/fakes.dart';
import '../helpers/fixtures.dart';

void main() {
  late FakeRecipeService service;
  late RecipeListViewModel vm;

  setUp(() async {
    service = FakeRecipeService();
    final storage = SecureStorage.inMemory();
    await storage.saveSession(accessToken: 'jwt', userId: 'user-42');
    vm = RecipeListViewModel(service: service, storage: storage);
  });

  Widget harness() => ChangeNotifierProvider<RecipeListViewModel>.value(
        value: vm,
        child: MaterialApp(
          home: const RecipeListPage(),
          routes: {
            AppRoutes.recipeDetail: (_) => const Scaffold(body: Text('DETAIL')),
          },
        ),
      );

  testWidgets('shows shimmer placeholders while loading', (tester) async {
    service.listDelay = const Duration(milliseconds: 100);
    await tester.pumpWidget(harness());

    await tester.pump();

    expect(find.byType(RecipeCardShimmer), findsWidgets);

    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    expect(find.byType(RecipeCardShimmer), findsNothing);
  });

  testWidgets('renders recipe cards with source badges', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('Paneer Butter Masala'), findsOneWidget);
    expect(find.text('Aloo Gobi'), findsOneWidget);
    expect(find.text('Chicken Biryani'), findsOneWidget);
    expect(find.text('AI'), findsNWidgets(2));
    expect(find.text('OWN'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no recipes',
      (tester) async {
    service.listResult = const Success([]);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(
      find.text('No recipes yet — tap Create to generate one!'),
      findsOneWidget,
    );
  });

  testWidgets('shows the error state with a working retry', (tester) async {
    service.listResult = const Failure('No connection');
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('No connection'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(service.listByUserCalls, 1);

    service.listResult = Success(sampleRecipes());
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Paneer Butter Masala'), findsOneWidget);
    expect(service.listByUserCalls, 2);
  });

  testWidgets('search filters the visible cards', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'paneer');
    await tester.pump();

    expect(find.text('Paneer Butter Masala'), findsOneWidget);
    expect(find.text('Aloo Gobi'), findsNothing);
    expect(find.text('Chicken Biryani'), findsNothing);
  });

  testWidgets('tap on a card opens the detail route', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Paneer Butter Masala'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paneer Butter Masala'));
    await tester.pumpAndSettle();

    expect(find.text('DETAIL'), findsOneWidget);
  });

  testWidgets('sort sheet changes the sort option', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alphabetical (A-Z)'));
    await tester.pumpAndSettle();

    expect(vm.sort, RecipeSortOption.alphabetical);
    expect(vm.visible.first.dishName, 'Aloo Gobi');
  });
}

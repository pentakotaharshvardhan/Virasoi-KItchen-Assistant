import 'package:ai_assistant_frontend/core/constants/app_colors.dart';
import 'package:ai_assistant_frontend/core/routes/app_routes.dart';
import 'package:ai_assistant_frontend/core/utils/result.dart';
import 'package:ai_assistant_frontend/view_models/recipe_detail_viewmodel.dart';
import 'package:ai_assistant_frontend/views/recipe/recipe_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/fakes.dart';
import '../helpers/fixtures.dart';

void main() {
  testWidgets('top-right Start button opens cooking with this dish selected',
      (tester) async {
    final service = FakeRecipeService()
      ..byIdResult = Success(sampleRecipe(dishName: 'Dal Makhani'));
    final viewModel = RecipeDetailViewModel(service: service);

    await tester.pumpWidget(
      ChangeNotifierProvider<RecipeDetailViewModel>.value(
        value: viewModel,
        child: MaterialApp(
          home: const RecipeDetailPage(recipeId: 'recipe-1'),
          onGenerateRoute: (settings) {
            if (settings.name == AppRoutes.createRecipe) {
              return MaterialPageRoute(
                builder: (_) => Scaffold(
                  body: Text('COOK:${settings.arguments}'),
                ),
              );
            }
            return null;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final startButton = find.byTooltip('Start cooking Dal Makhani');
    expect(startButton, findsOneWidget);
    final startCenter = tester.getCenter(startButton);
    expect(
        startCenter.dx,
        greaterThan(
            tester.view.physicalSize.width / tester.view.devicePixelRatio / 2));
    expect(startCenter.dy, lessThan(200));
    expect(tester.widget<Text>(find.text('Start')).style?.color,
        AppColors.warning);

    await tester.tap(startButton);
    await tester.pumpAndSettle();

    expect(find.text('COOK:Dal Makhani'), findsOneWidget);
  });
}

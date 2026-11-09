import 'package:ai_assistant_frontend/core/utils/secure_storage.dart';
import 'package:ai_assistant_frontend/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    SecureStorage.instance = SecureStorage.inMemory();
  });

  tearDown(() {
    SecureStorage.reset();
  });

  testWidgets('new installs land on the login screen', (tester) async {
    await tester.pumpWidget(const AiAssistantApp());
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
  });

  testWidgets('a stored token lands on the home screen', (tester) async {
    await SecureStorage.instance.saveSession(
      accessToken: 'stored-token',
      userName: 'Harsh Chef',
      userId: 'u-1',
    );

    await tester.pumpWidget(const AiAssistantApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Hey, Harsh'), findsOneWidget);
    expect(find.text('Your Recipes'), findsOneWidget);
    expect(find.text('Add a recipe or start cooking'), findsNothing);

    final addButton = find.byType(FloatingActionButton);
    expect(addButton, findsOneWidget);
    expect(tester.widget<FloatingActionButton>(addButton).shape,
        isA<CircleBorder>());
    final buttonSize = tester.getSize(addButton);
    expect(buttonSize.width, buttonSize.height);
    expect(
      tester.getCenter(addButton).dx,
      closeTo(
        tester.view.physicalSize.width / tester.view.devicePixelRatio / 2,
        1,
      ),
    );

    // Unmount so the home screen's looping animations stop.
    await tester.pumpWidget(const SizedBox());
  });
}

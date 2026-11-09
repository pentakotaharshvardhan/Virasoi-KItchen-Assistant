import 'package:ai_assistant_frontend/core/utils/secure_storage.dart';
import 'package:ai_assistant_frontend/view_models/home_viewmodel.dart';
import 'package:ai_assistant_frontend/widgets/app_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('drawer shows profile and requested navigation only',
      (tester) async {
    final storage = SecureStorage.inMemory();
    await storage.saveSession(
      accessToken: 'token',
      userId: 'user-1',
      userName: 'Test Chef',
      userEmail: 'chef@example.com',
    );
    final home = HomeViewModel(storage: storage);
    await home.loadUser();

    await tester.pumpWidget(
      ChangeNotifierProvider<HomeViewModel>.value(
        value: home,
        child: MaterialApp(
          home: Scaffold(
            drawer: const AppDrawer(),
            body: Builder(
              builder: (context) => IconButton(
                onPressed: () => Scaffold.of(context).openDrawer(),
                icon: const Icon(Icons.menu),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(find.text('Test Chef'), findsOneWidget);
    expect(find.text('chef@example.com'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('FAQ'), findsOneWidget);
    expect(find.text('App Guide'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
    expect(find.text('My Recipes'), findsNothing);
    expect(find.text('Helper'), findsNothing);
  });
}

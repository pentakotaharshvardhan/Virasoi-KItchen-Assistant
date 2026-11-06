import 'package:ai_assistant_frontend/core/network/api_client.dart';
import 'package:ai_assistant_frontend/core/routes/app_routes.dart';
import 'package:ai_assistant_frontend/core/utils/secure_storage.dart';
import 'package:ai_assistant_frontend/services/auth_service.dart';
import 'package:ai_assistant_frontend/view_models/auth_viewmodel.dart';
import 'package:ai_assistant_frontend/views/auth/register_page.dart';
import 'package:ai_assistant_frontend/widgets/gradient_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../helpers/fakes.dart';

void main() {
  setUp(() {
    SecureStorage.instance = SecureStorage.inMemory();
  });

  tearDown(() {
    SecureStorage.reset();
  });

  Widget harness(MockClient client) {
    final vm = AuthViewModel(
      authService: AuthService(api: ApiClient.withClient(client)),
    );
    return ChangeNotifierProvider<AuthViewModel>.value(
      value: vm,
      child: MaterialApp(
        home: const RegisterPage(),
        routes: {
          AppRoutes.home: (_) => const Scaffold(body: Text('HOME')),
        },
      ),
    );
  }

  Future<void> fill(
    WidgetTester tester, {
    String username = 'newchef',
    String email = 'new@example.com',
    String password = 'secret1',
  }) async {
    await tester.enterText(find.byType(TextFormField).at(0), username);
    await tester.enterText(find.byType(TextFormField).at(1), email);
    await tester.enterText(find.byType(TextFormField).at(2), password);
  }

  testWidgets('renders the registration form', (tester) async {
    await tester.pumpWidget(harness(MockClient((_) async => jsonResponse({}))));
    await tester.pumpAndSettle();

    expect(find.text('Join the kitchen'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(find.widgetWithText(GradientButton, 'Create account'), findsOneWidget);
  });

  testWidgets('validates username, email and password before calling the API', (tester) async {
    var calls = 0;
    await tester.pumpWidget(harness(MockClient((_) async {
      calls++;
      return jsonResponse({});
    })));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(GradientButton, 'Create account'));
    await tester.pump();

    expect(find.text('Enter a username'), findsOneWidget);
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('Min. 6 characters'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('rejects a malformed email', (tester) async {
    await tester.pumpWidget(harness(MockClient((_) async => jsonResponse({}))));
    await tester.pumpAndSettle();

    await fill(tester, email: 'not-an-email');
    await tester.tap(find.widgetWithText(GradientButton, 'Create account'));
    await tester.pump();

    expect(find.text('Enter a valid email'), findsOneWidget);
  });

  testWidgets('successful registration stores the token and navigates home', (tester) async {
    await tester.pumpWidget(harness(MockClient((request) async {
      expect(request.url.path, '/api/auth/register');
      return jsonResponse({'token': 'jwt-2', 'userId': 'u-2', 'username': 'newchef'});
    })));
    await tester.pumpAndSettle();

    await fill(tester);
    await tester.tap(find.widgetWithText(GradientButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(find.text('HOME'), findsOneWidget);
    expect(await SecureStorage.instance.accessToken, 'jwt-2');
  });

  testWidgets('failed registration surfaces the backend error', (tester) async {
    await tester.pumpWidget(harness(MockClient(
      (_) async => jsonResponse({'message': 'Username taken'}, status: 409),
    )));
    await tester.pumpAndSettle();

    await fill(tester);
    await tester.tap(find.widgetWithText(GradientButton, 'Create account'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.text('Username taken'), findsOneWidget);
  });
}

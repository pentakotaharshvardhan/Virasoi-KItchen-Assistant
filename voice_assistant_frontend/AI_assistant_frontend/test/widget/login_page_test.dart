import 'package:ai_assistant_frontend/core/network/api_client.dart';
import 'package:ai_assistant_frontend/core/routes/app_routes.dart';
import 'package:ai_assistant_frontend/core/utils/secure_storage.dart';
import 'package:ai_assistant_frontend/services/auth_service.dart';
import 'package:ai_assistant_frontend/view_models/auth_viewmodel.dart';
import 'package:ai_assistant_frontend/views/auth/login_page.dart';
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
        home: const LoginPage(),
        routes: {
          AppRoutes.home: (_) => const Scaffold(body: Text('HOME')),
          AppRoutes.register: (_) => const Scaffold(body: Text('REGISTER')),
        },
      ),
    );
  }

  testWidgets('renders the sign-in form', (tester) async {
    await tester.pumpWidget(harness(MockClient((_) async => jsonResponse({}))));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in to your kitchen assistant'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Log In'), findsOneWidget);
  });

  testWidgets('empty submit shows both validation errors and calls no API', (tester) async {
    var calls = 0;
    await tester.pumpWidget(harness(MockClient((_) async {
      calls++;
      return jsonResponse({});
    })));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Log In'));
    await tester.pump();

    expect(find.text('Enter a username'), findsOneWidget);
    expect(find.text('Min. 6 characters'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('rejects a password shorter than six characters', (tester) async {
    await tester.pumpWidget(harness(MockClient((_) async => jsonResponse({}))));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'chef');
    await tester.enterText(find.byType(TextFormField).at(1), '123');
    await tester.tap(find.text('Log In'));
    await tester.pump();

    expect(find.text('Min. 6 characters'), findsOneWidget);
  });

  testWidgets('successful login persists the token and navigates home', (tester) async {
    await tester.pumpWidget(harness(MockClient((request) async {
      expect(request.url.path, '/api/auth/login');
      return jsonResponse({'token': 'jwt-1', 'userId': 'u-1', 'username': 'chef'});
    })));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'chef');
    await tester.enterText(find.byType(TextFormField).at(1), 'secret1');
    await tester.tap(find.text('Log In'));
    await tester.pumpAndSettle();

    expect(find.text('HOME'), findsOneWidget);
    expect(await SecureStorage.instance.accessToken, 'jwt-1');
  });

  testWidgets('failed login shows the backend message in a SnackBar', (tester) async {
    await tester.pumpWidget(harness(MockClient(
      (_) async => jsonResponse({'message': 'Bad credentials'}, status: 401),
    )));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'chef');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong12');
    await tester.tap(find.text('Log In'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.text('Bad credentials'), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
  });

  testWidgets('password visibility toggle flips obscureText', (tester) async {
    await tester.pumpWidget(harness(MockClient((_) async => jsonResponse({}))));
    await tester.pumpAndSettle();

    EditableText passwordField() =>
        tester.widget<EditableText>(find.byType(EditableText).at(1));

    expect(passwordField().obscureText, isTrue);

    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pump();

    expect(passwordField().obscureText, isFalse);
  });

  testWidgets('register link opens the register route', (tester) async {
    await tester.pumpWidget(harness(MockClient((_) async => jsonResponse({}))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();

    expect(find.text('REGISTER'), findsOneWidget);
  });
}

import 'dart:convert';

import 'package:ai_assistant_frontend/core/network/api_client.dart';
import 'package:ai_assistant_frontend/core/routes/app_routes.dart';
import 'package:ai_assistant_frontend/core/utils/result.dart';
import 'package:ai_assistant_frontend/core/utils/secure_storage.dart';
import 'package:ai_assistant_frontend/models/ingredient_model.dart';
import 'package:ai_assistant_frontend/view_models/ingredient_viewmodel.dart';
import 'package:ai_assistant_frontend/view_models/voice_viewmodel.dart';
import 'package:ai_assistant_frontend/views/ingredient/ingredient_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../helpers/fakes.dart';
import '../helpers/fixtures.dart';

void main() {
  late FakeIngredientService ingredients;
  late FakeUnsplashService unsplash;
  late FakeVoiceEngine voice;
  late FakeAiService ai;
  late FakeWebSocket ws;
  late IngredientViewModel vm;
  late VoiceViewModel voiceVm;
  late SecureStorage storage;

  setUp(() {
    SecureStorage.instance = SecureStorage.inMemory();
    storage = SecureStorage.instance;
    ingredients = FakeIngredientService();
    unsplash = FakeUnsplashService();
    voice = FakeVoiceEngine();
    ai = FakeAiService();
    ws = FakeWebSocket();

    ingredients.result = Success(
      recipeWithIngredients([
        IngredientModel(
          id: 'ing-onion',
          name: 'Onion',
          quantityPerServe: 2,
          unit: 'pcs',
          dishNames: ['Test Dish'],
        ),
        IngredientModel(
          id: 'ing-salt',
          name: 'Salt',
          quantityPerServe: 1,
          unit: 'tsp',
          dishNames: ['Test Dish'],
        ),
      ]),
    );

    vm = IngredientViewModel(
      ingredientService: ingredients,
      unsplash: unsplash,
      api: ApiClient.withClient(MockClient((request) async {
        if (request.method == 'POST') {
          return http.Response(jsonEncode({'sessionId': 'sess-1'}), 200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('{}', 200,
            headers: {'content-type': 'application/json'});
      })),
      storage: storage,
      wsFactory: (url, token) => ws,
    );

    voiceVm = VoiceViewModel(
      voice: voice,
      aiService: ai,
      storage: storage,
      wsFactory: (url, token) => ws,
    );
  });

  tearDown(SecureStorage.reset);

  Widget harness() => MultiProvider(
        providers: [
          ChangeNotifierProvider<IngredientViewModel>.value(value: vm),
          ChangeNotifierProvider<VoiceViewModel>.value(value: voiceVm),
        ],
        child: MaterialApp(
          home: const IngredientPage(recipeIds: ['r1']),
          onGenerateRoute: (settings) {
            if (settings.name == AppRoutes.voiceAssistant) {
              return MaterialPageRoute(
                builder: (_) => Scaffold(
                  body: Text('COOK:${settings.arguments}'),
                ),
              );
            }
            return null;
          },
        ),
      );

  testWidgets('an unconfirmed ingredient no longer traps the user on the screen',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('Onion'), findsOneWidget);
    final button = find.text('Continue to cooking (2 left)');
    expect(button, findsOneWidget);

    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.textContaining('COOK:'), findsOneWidget);
    expect(find.textContaining('awaitingReady: true'), findsOneWidget);
    expect(vm.sessionId, 'sess-1');
  });

  testWidgets('the button switches to "Start cooking" when nothing is left',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    vm.markConfirmedByNames(['Onion', 'Salt']);
    await tester.pump();

    expect(vm.pending, isEmpty);
    expect(find.text('Start cooking'), findsOneWidget);

    // Let the scheduled hand-off fire so no timer is left pending at teardown.
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    expect(find.textContaining('COOK:'), findsOneWidget);
  });

  testWidgets('a voice removal confirms the card and shows what changed',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(voiceVm.onIngredientsRemoved, isNotNull);
    voiceVm.onIngredientsRemoved!(['Onion']);

    await tester.pump();
    expect(find.text('Removed from the list: Onion'), findsOneWidget);
    expect(vm.pending.map((i) => i.name), ['Salt']);

    await tester.pumpAndSettle();
  });

  testWidgets('confirming everything moves on to cooking by itself',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    voiceVm.onIngredientsRemoved!(['Onion', 'Salt']);

    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    expect(find.textContaining('COOK:'), findsOneWidget);
  });
}

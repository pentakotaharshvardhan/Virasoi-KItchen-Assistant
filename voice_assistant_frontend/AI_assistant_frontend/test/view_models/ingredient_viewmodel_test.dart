import 'dart:convert';

import 'package:ai_assistant_frontend/core/network/api_client.dart';
import 'package:ai_assistant_frontend/core/utils/result.dart';
import 'package:ai_assistant_frontend/core/utils/secure_storage.dart';
import 'package:ai_assistant_frontend/models/ingredient_model.dart';
import 'package:ai_assistant_frontend/view_models/ingredient_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import '../helpers/fakes.dart';
import '../helpers/fixtures.dart';

void main() {
  late FakeIngredientService ingredientService;
  late FakeUnsplashService unsplash;
  late FakeWebSocket ws;
  late SecureStorage storage;
  late int dishCalls;
  late Map<String, dynamic> lastSessionBody;
  late Map<String, dynamic> lastDishBody;

  IngredientModel onion() =>
      IngredientModel.fromJson(ingredientJson(id: 'i1', name: 'Onion'));
  IngredientModel tomato() =>
      IngredientModel.fromJson(ingredientJson(id: 'i2', name: 'Tomato'));

  ApiClient buildApi({int startStatus = 200}) {
    return ApiClient.withClient(MockClient((request) async {
      if (request.url.path == '/api/sessions/start') {
        lastSessionBody = jsonDecode(request.body) as Map<String, dynamic>;
        if (startStatus != 200) {
          return jsonResponse({'message': 'Cannot start session'},
              status: startStatus);
        }
        return jsonResponse({'sessionId': 'sess-1'});
      }
      if (request.url.path == '/api/sessions/sess-1/dishes') {
        dishCalls++;
        lastDishBody = jsonDecode(request.body) as Map<String, dynamic>;
        return jsonResponse({});
      }
      return jsonResponse({}, status: 404);
    }));
  }

  IngredientViewModel buildViewModel({ApiClient? api}) => IngredientViewModel(
        ingredientService: ingredientService,
        unsplash: unsplash,
        api: api ?? buildApi(),
        storage: storage,
        wsFactory: (url, token) => ws,
      );

  /// Loads the view model and lets the async `connectLiveSync` subscribe to
  /// the socket before the test emits messages on it.
  Future<IngredientViewModel> loaded({ApiClient? api}) async {
    final vm = buildViewModel(api: api);
    await vm.load(['recipe-ing']);
    await Future<void>.delayed(Duration.zero);
    return vm;
  }

  setUp(() {
    ingredientService = FakeIngredientService();
    unsplash = FakeUnsplashService();
    ws = FakeWebSocket();
    storage = SecureStorage.inMemory();
    dishCalls = 0;
    lastSessionBody = {};
    lastDishBody = {};
    ingredientService.result =
        Success(recipeWithIngredients([onion(), tomato()]));
  });

  test(
      'load fetches ingredients, starts a session and connects live sync without cooking',
      () async {
    await storage.saveSession(accessToken: 'jwt', userId: 'u-1');
    final vm = buildViewModel();

    await vm.load(['recipe-ing']);
    await Future<void>.delayed(Duration.zero);

    expect(vm.isLoading, isFalse);
    expect(vm.pending.map((i) => i.name), ['Onion', 'Tomato']);
    expect(vm.sessionId, 'sess-1');
    expect(lastSessionBody['userId'], 'u-1');
    expect(lastSessionBody['numberOfStoves'], 1);
    expect(dishCalls, 0,
        reason: 'cooking must not start while gathering ingredients');
    expect(ws.connected, isTrue);
    expect(ingredientService.lastRecipeId, 'recipe-ing');
  });

  test(
      'startCooking adds the dish using the stoves/servings saved on the setup screen',
      () async {
    await storage.saveSettings(stoves: 3, servings: 4);
    final vm = buildViewModel();

    await vm.load(['recipe-ing']);
    await Future<void>.delayed(Duration.zero);
    expect(lastSessionBody['numberOfStoves'], 3);

    final ok = await vm.startCooking();

    expect(ok, isTrue);
    expect(dishCalls, 1);
    expect(lastDishBody['dishName'], 'Test Dish');
    expect(lastDishBody['servesRequested'], 4);
  });

  test('load enriches each ingredient with an Unsplash photo', () async {
    final vm = buildViewModel();

    await vm.load(['recipe-ing']);
    await Future<void>.delayed(Duration.zero);

    expect(unsplash.queries, ['Onion', 'Tomato']);
    expect(
        vm.pending
            .every((i) => i.imageUrl == 'https://images.example.test/item.jpg'),
        isTrue);
  });

  test('a null Unsplash result leaves the placeholder image', () async {
    unsplash.url = null;
    final vm = buildViewModel();

    await vm.load(['recipe-ing']);
    await Future<void>.delayed(Duration.zero);

    expect(vm.pending.every((i) => i.imageUrl == null), isTrue);
  });

  test('load failure surfaces the error and never opens a socket', () async {
    ingredientService.result = const Failure('Recipe missing');
    final vm = buildViewModel();

    await vm.load(['nope']);

    expect(vm.isLoading, isFalse);
    expect(vm.errorMessage, 'Recipe missing');
    expect(vm.sessionId, isNull);
    expect(ws.connected, isFalse);
  });

  test('session start failure leaves the screen usable without live sync',
      () async {
    final vm = buildViewModel(api: buildApi(startStatus: 500));

    await vm.load(['recipe-ing']);

    expect(vm.isLoading, isFalse);
    expect(vm.pending.length, 2);
    expect(vm.sessionId, isNull);
    expect(ws.connected, isFalse);
  });

  test('a missing sessionId in the response is ignored safely', () async {
    final api = ApiClient.withClient(MockClient((request) async {
      if (request.url.path == '/api/sessions/start') return jsonResponse({});
      return jsonResponse({});
    }));
    final vm = buildViewModel(api: api);

    await vm.load(['recipe-ing']);

    expect(vm.sessionId, isNull);
    expect(ws.connected, isFalse);
  });

  test('item_confirmed removes the matching card', () async {
    final vm = await loaded();

    ws.emit({'type': 'item_confirmed', 'itemName': 'onion'});
    await Future<void>.delayed(Duration.zero);

    expect(vm.pending.map((i) => i.name), ['Tomato']);
    expect(vm.confirmed.single.name, 'Onion');
    expect(vm.confirmed.single.isConfirmedAvailable, isTrue);
  });

  test('item_missing adds the item to the shopping banner once', () async {
    final vm = await loaded();

    ws.emit({'type': 'item_missing', 'itemName': 'Coriander'});
    ws.emit({'type': 'item_missing', 'itemName': 'Coriander'});
    await Future<void>.delayed(Duration.zero);

    expect(vm.missingItems, ['Coriander']);
  });

  test('REMOVE command confirms the ingredient by name', () async {
    final vm = await loaded();

    ws.emit({'command': 'REMOVE', 'ingredientName': 'Tomato'});
    await Future<void>.delayed(Duration.zero);

    expect(vm.pending.map((i) => i.name), ['Onion']);
    expect(vm.confirmed.single.name, 'Tomato');
  });

  test('REMOVE command wrapped in data is also handled', () async {
    final vm = await loaded();

    ws.emit({
      'command': 'REMOVE',
      'data': {'ingredientName': 'Onion'},
    });
    await Future<void>.delayed(Duration.zero);

    expect(vm.confirmed.single.name, 'Onion');
  });

  test('remove_ingredient broadcast from the backend removes the matching card',
      () async {
    final vm = await loaded();

    ws.emit({
      'type': 'remove_ingredient',
      'data': {'ingredientName': 'onion', 'message': 'Okay, removing onion.'},
    });
    await Future<void>.delayed(Duration.zero);

    expect(vm.pending.map((i) => i.name), ['Tomato']);
    expect(vm.confirmed.single.name, 'Onion');
  });

  test('fuzzy matching handles plurals and partial names', () async {
    ingredientService.result = Success(recipeWithIngredients([
      IngredientModel.fromJson(ingredientJson(id: 'i3', name: 'Onions')),
      IngredientModel.fromJson(
          ingredientJson(id: 'i4', name: 'Ginger-Garlic Paste')),
    ]));
    final vm = await loaded();

    ws.emit({
      'type': 'remove_ingredient',
      'data': {'ingredientName': 'onion'}
    });
    ws.emit({
      'type': 'remove_ingredient',
      'data': {'ingredientName': 'garlic'}
    });
    await Future<void>.delayed(Duration.zero);

    expect(vm.pending, isEmpty);
    expect(vm.confirmed.map((i) => i.name), ['Onions', 'Ginger-Garlic Paste']);
  });

  test('a multi-ingredient remove_ingredient broadcast clears every named item',
      () async {
    final vm = await loaded();

    ws.emit({
      'type': 'remove_ingredient',
      'data': {
        'ingredientNames': ['onion', 'tomato'],
        'ingredientName': 'onion',
        'message': 'Okay, removing onion and tomato from your list.',
      },
    });
    await Future<void>.delayed(Duration.zero);

    expect(vm.pending, isEmpty);
    expect(vm.confirmed.map((i) => i.name), ['Onion', 'Tomato']);
    expect(vm.remainingNames, isEmpty);
  });

  test('a likely spelling error resolves to the unique checklist item',
      () async {
    ingredientService.result = Success(recipeWithIngredients([
      IngredientModel.fromJson(ingredientJson(id: 'i3', name: 'Paneer')),
      IngredientModel.fromJson(ingredientJson(id: 'i4', name: 'Tomato')),
    ]));
    final vm = await loaded();

    vm.markConfirmedByNames(['panner']);

    expect(vm.confirmed.map((item) => item.name), ['Paneer']);
    expect(vm.pending.map((item) => item.name), ['Tomato']);
  });

  test('an ambiguous spelling does not remove a checklist item', () async {
    ingredientService.result = Success(recipeWithIngredients([
      IngredientModel.fromJson(ingredientJson(id: 'i3', name: 'Cheesy Paneer')),
      IngredientModel.fromJson(ingredientJson(id: 'i4', name: 'Spicy Paneer')),
    ]));
    final vm = await loaded();

    vm.markConfirmedByNames(['panner']);

    expect(
        vm.pending.map((item) => item.name), ['Cheesy Paneer', 'Spicy Paneer']);
    expect(vm.confirmed, isEmpty);
  });

  test('a single-name field containing a list removes each matching item',
      () async {
    final vm = await loaded();

    ws.emit({
      'type': 'remove_ingredient',
      'data': {'ingredientName': 'onions and tomatoes'},
    });
    await Future<void>.delayed(Duration.zero);

    expect(vm.pending, isEmpty);
    expect(vm.confirmed.map((item) => item.name), ['Onion', 'Tomato']);
  });

  test('batch matching prefers exact matches before partial matches', () async {
    ingredientService.result = Success(recipeWithIngredients([
      IngredientModel.fromJson(ingredientJson(id: 'i5', name: 'Garlic Paste')),
      IngredientModel.fromJson(ingredientJson(id: 'i6', name: 'Garlic')),
    ]));
    final vm = await loaded();

    ws.emit({
      'type': 'remove_ingredient',
      'data': {
        'ingredientNames': ['garlic', 'garlic paste'],
      },
    });
    await Future<void>.delayed(Duration.zero);

    expect(vm.pending, isEmpty);
    expect(vm.confirmed.map((item) => item.name), ['Garlic Paste', 'Garlic']);
  });

  test('remainingNames lists whatever has not been gathered yet', () async {
    final vm = await loaded();

    expect(vm.remainingNames, ['Onion', 'Tomato']);

    ws.emit({'type': 'item_confirmed', 'itemName': 'Onion'});
    await Future<void>.delayed(Duration.zero);

    expect(vm.remainingNames, ['Tomato']);
  });

  test('an unknown ingredient name is ignored', () async {
    final vm = await loaded();

    ws.emit({'type': 'item_confirmed', 'itemName': 'Unicorn'});
    await Future<void>.delayed(Duration.zero);

    expect(vm.pending.length, 2);
    expect(vm.confirmed, isEmpty);
  });

  test('removeIngredient removes by id', () async {
    final vm = await loaded();

    vm.removeIngredient('i1');

    expect(vm.pending.map((i) => i.name), ['Tomato']);
  });

  test('isDoneConfirming becomes true after every item is confirmed', () async {
    final vm = await loaded();

    expect(vm.isDoneConfirming, isFalse);

    ws.emit({'type': 'item_confirmed', 'itemName': 'Onion'});
    ws.emit({'type': 'item_confirmed', 'itemName': 'Tomato'});
    await Future<void>.delayed(Duration.zero);

    expect(vm.isDoneConfirming, isTrue);
  });

  test('dispose closes the socket', () async {
    final vm = await loaded();

    vm.dispose();

    expect(ws.disposeCalls, 1);
  });

  group('multi-dish meal', () {
    void seedTwoDishes() {
      ingredientService.resultById['r-a'] = Success(recipeWithIngredients([
        IngredientModel.fromJson(
            ingredientJson(id: 'i1', name: 'Onion', quantityPerServe: 2)),
        IngredientModel.fromJson(
            ingredientJson(id: 'i2', name: 'Tomato', quantityPerServe: 1)),
      ], id: 'r-a', dishName: 'Paneer Masala'));
      ingredientService.resultById['r-b'] = Success(recipeWithIngredients([
        IngredientModel.fromJson(
            ingredientJson(id: 'i1', name: 'Onion', quantityPerServe: 3)),
        IngredientModel.fromJson(
            ingredientJson(id: 'i3', name: 'Salt', quantityPerServe: 0.5)),
      ], id: 'r-b', dishName: 'Dal'));
    }

    test('the same item across dishes becomes ONE card with the combined total',
        () async {
      seedTwoDishes();
      final vm = buildViewModel();

      await vm.load(['r-a', 'r-b']);
      await Future<void>.delayed(Duration.zero);

      expect(ingredientService.requestedIds, ['r-a', 'r-b']);
      expect(vm.pending.map((i) => i.name), ['Onion', 'Tomato', 'Salt']);

      final onion = vm.pending.first;
      expect(onion.quantityPerServe, 5, reason: '2 pcs + 3 pcs = 5 pcs');
      expect(onion.dishNames, ['Paneer Masala', 'Dal']);
      expect(vm.dishCount, 2);
      expect(
        unsplash.queries,
        ['Onion', 'Tomato', 'Salt'],
        reason: 'a merged item is photographed once, not per dish',
      );
    });

    test('startCooking adds every dish of the meal to the session', () async {
      seedTwoDishes();
      final vm = buildViewModel();

      await vm.load(['r-a', 'r-b']);
      await Future<void>.delayed(Duration.zero);

      final ok = await vm.startCooking();

      expect(ok, isTrue);
      expect(dishCalls, 2);
      expect(lastDishBody['dishName'], 'Dal');
    });

    test('a failing recipe load surfaces the error and never starts a session',
        () async {
      ingredientService.resultById['r-b'] = const Failure('Recipe missing');
      final vm = buildViewModel();

      await vm.load(['r-a', 'r-b']);

      expect(vm.isLoading, isFalse);
      expect(vm.errorMessage, 'Recipe missing');
      expect(vm.sessionId, isNull);
      expect(ws.connected, isFalse);
    });
  });
}

import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/network/api_client.dart';
import '../core/network/websocket_service.dart';
import '../core/utils/result.dart';
import '../core/utils/secure_storage.dart';
import '../models/ingredient_model.dart';
import '../services/ingredient_service.dart';
import '../services/unsplash_service.dart';

/// Drives the "gather ingredients" flow (screen 6):
///  - loads the recipe's required ingredient list w/ Unsplash photos
///  - listens on a websocket so that, as the voice assistant hears the user
///    name items they already have, matching cards disappear from the grid
///  - tracks which required items are still missing, so we can tell the
///    user which ones to go buy before continuing to the voice screen
class IngredientViewModel extends ChangeNotifier {
  IngredientViewModel({
    IngredientService? ingredientService,
    UnsplashService? unsplash,
    ApiClient? api,
    SecureStorage? storage,
    AppWebSocketService Function(String url, String? token)? wsFactory,
  })  : _ingredientService = ingredientService ?? IngredientService(),
        _unsplash = unsplash ?? UnsplashService(),
        _api = api ?? ApiClient.instance,
        _storage = storage ?? SecureStorage.instance,
        _wsFactory = wsFactory ??
            ((url, token) => AppWebSocketService(url: url, token: token));

  final IngredientService _ingredientService;
  final UnsplashService _unsplash;
  final ApiClient _api;
  final SecureStorage _storage;
  final AppWebSocketService Function(String url, String? token) _wsFactory;
  AppWebSocketService? _ws;

  bool isLoading = true;
  String? errorMessage;
  List<IngredientModel> pending = [];
  List<IngredientModel> confirmed = [];
  List<String> missingItems = [];
  String? sessionId;

  Future<void> load(String recipeId) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    
    // 1. Load recipe and ingredients
    final result = await _ingredientService.getRecipeWithIngredients(recipeId);
    String? recipeDishName;
    
    switch (result) {
      case Success(data: final recipe):
        pending = recipe.ingredients;
        recipeDishName = recipe.dishName;
        // Fetch Unsplash photos in background
        for (final item in pending) {
          _unsplash.fetchImageUrl(item.name).then((url) {
            if (url == null) return;
            item.imageUrl = url;
            notifyListeners();
          });
        }
        break;
      case Failure(message: final m):
        errorMessage = m;
        isLoading = false;
        notifyListeners();
        return;
    }

    // 2. Start a cooking session to get a valid sessionId for WebSocket
    final userId = await _storage.userId;
    final sessionRes = await _api.post(ApiConstants.startSession, body: {
      'userId': userId,
      'numberOfStoves': 1, // Default
    });

    switch (sessionRes) {
      case Success(data: final data):
        final rawId = data['sessionId'] ?? data['id'];
        if (rawId != null) {
          sessionId = rawId.toString();
          // 3. Add the recipe as a dish to this session so the backend knows what we are cooking
          await _api.post(ApiConstants.sessionDishes(sessionId!), body: {
            'dishName': recipeDishName,
            'servesRequested': 1, // Default
          });
          
          connectLiveSync(sessionId!);
        }
        break;
      case Failure():
        break;
    }

    isLoading = false;
    notifyListeners();
  }

  /// Optional live sync: server tells us (via websocket, driven by the
  /// voice assistant) which item names the user just confirmed they have.
  void connectLiveSync(String sid) async {
    final token = await _storage.accessToken;
    _ws = _wsFactory(ApiConstants.wsVoiceAssistant(token ?? '', sid), token);
    _ws!.connect();
    _ws!.messages.listen((msg) {
      final type = msg['type']?.toString();
      final command = msg['command']?.toString();
      final data = msg['data'] as Map<String, dynamic>?;

      if (type == 'item_confirmed') {
        markConfirmedByName(msg['itemName']?.toString() ?? '');
      } else if (type == 'item_missing') {
        final name = msg['itemName']?.toString();
        if (name != null && !missingItems.contains(name)) missingItems.add(name);
        notifyListeners();
      } else if (command == 'REMOVE') {
        final ingName = msg['ingredientName']?.toString() ?? data?['ingredientName']?.toString();
        if (ingName != null) markConfirmedByName(ingName);
      }
    });
  }

  void markConfirmedByName(String name) {
    final idx = pending.indexWhere((i) => i.name.toLowerCase() == name.toLowerCase());
    if (idx == -1) return;
    final item = pending.removeAt(idx);
    item.isConfirmedAvailable = true;
    confirmed.add(item);
    notifyListeners();
  }

  /// Manually remove an ingredient from the pending grid by ID
  void removeIngredient(String id) {
    pending.removeWhere((i) => i.id == id);
    notifyListeners();
  }

  bool get isDoneConfirming => pending.isEmpty;

  @override
  void dispose() {
    _ws?.dispose();
    super.dispose();
  }
}

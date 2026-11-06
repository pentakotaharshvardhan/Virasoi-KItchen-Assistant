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

  String? _dishName;
  int _serves = 1;
  int _stoveCount = 1;

  Future<void> load(String recipeId) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    // Use the stoves/servings the user picked on the setup screen instead of hard-coded defaults.
    _stoveCount = await _storage.stoveCount;
    _serves = await _storage.servingCount;

    // 1. Load recipe and ingredients
    final result = await _ingredientService.getRecipeWithIngredients(recipeId);
    
    switch (result) {
      case Success(data: final recipe):
        pending = recipe.ingredients;
        _dishName = recipe.dishName;
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

    // 2. Start a cooking session to get a valid sessionId for WebSocket. The dish is deliberately
    //    NOT added yet - cooking must not start while the user is still gathering ingredients.
    final userId = await _storage.userId;
    final sessionRes = await _api.post(ApiConstants.startSession, body: {
      'userId': userId,
      'numberOfStoves': _stoveCount < 1 ? 1 : _stoveCount,
    });

    switch (sessionRes) {
      case Success(data: final data):
        final rawId = data['sessionId'] ?? data['id'];
        if (rawId != null) {
          sessionId = rawId.toString();
          connectLiveSync(sessionId!);
        } else {
          errorMessage = 'Could not start a cooking session.';
        }
        break;
      case Failure(message: final m):
        errorMessage = m;
        break;
    }

    isLoading = false;
    notifyListeners();
  }

  /// Adds the dish to the already-created session, which kicks off scheduling. Called when the
  /// user has confirmed every ingredient and is transitioning to the cooking screen.
  Future<bool> startCooking() async {
    if (sessionId == null || _dishName == null) return false;
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    final res = await _api.post(ApiConstants.sessionDishes(sessionId!), body: {
      'dishName': _dishName,
      'servesRequested': _serves < 1 ? 1 : _serves,
    });

    isLoading = false;
    switch (res) {
      case Success():
        notifyListeners();
        return true;
      case Failure(message: final m):
        errorMessage = m;
        notifyListeners();
        return false;
    }
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

      if (type == 'remove_ingredient') {
        final name = data?['ingredientName']?.toString() ?? msg['ingredientName']?.toString();
        if (name != null && name.trim().isNotEmpty) markConfirmedByName(name);
      } else if (type == 'item_confirmed') {
        final name = data?['itemName']?.toString() ?? msg['itemName']?.toString();
        if (name != null) markConfirmedByName(name);
      } else if (type == 'item_missing') {
        final name = data?['itemName']?.toString() ?? msg['itemName']?.toString();
        if (name != null && !missingItems.contains(name)) {
          missingItems.add(name);
          notifyListeners();
        }
      } else if (command == 'REMOVE') {
        final ingName = msg['ingredientName']?.toString() ?? data?['ingredientName']?.toString();
        if (ingName != null) markConfirmedByName(ingName);
      }
    });
  }

  void markConfirmedByName(String name) {
    final query = name.trim().toLowerCase();
    if (query.isEmpty) return;

    // 1. exact match, then 2. fuzzy (plurals / partial names like "garlic" vs "ginger-garlic paste").
    int idx = pending.indexWhere((i) => i.name.toLowerCase() == query);
    if (idx == -1) {
      idx = pending.indexWhere((i) => _namesMatch(i.name.toLowerCase(), query));
    }
    if (idx == -1) return;

    final item = pending.removeAt(idx);
    item.isConfirmedAvailable = true;
    confirmed.add(item);
    notifyListeners();
  }

  bool _namesMatch(String item, String query) {
    String singular(String s) {
      if (s.endsWith('ies') && s.length > 3) return '${s.substring(0, s.length - 3)}y';
      if (s.endsWith('es') && s.length > 2) return s.substring(0, s.length - 2);
      if (s.endsWith('s') && s.length > 1) return s.substring(0, s.length - 1);
      return s;
    }

    final a = singular(item);
    final b = singular(query);
    return a == b || a.contains(b) || b.contains(a);
  }

  /// Manually remove an ingredient from the pending grid by ID
  void removeIngredient(String id) {
    pending.removeWhere((i) => i.id == id);
    notifyListeners();
  }

  bool get isDoneConfirming => pending.isEmpty;

  void stopLiveSync() {
    _ws?.dispose();
    _ws = null;
  }

  @override
  void dispose() {
    stopLiveSync();
    super.dispose();
  }
}

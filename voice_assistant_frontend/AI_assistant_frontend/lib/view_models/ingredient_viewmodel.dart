import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/network/api_client.dart';
import '../core/network/websocket_service.dart';
import '../core/utils/result.dart';
import '../core/utils/secure_storage.dart';
import '../models/ingredient_model.dart';
import '../models/recipe_model.dart';
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

  /// Dishes of the current meal - every one is added to the cooking session.
  List<String> _dishNames = [];
  int _serves = 1;
  int _stoveCount = 1;

  int get dishCount => _dishNames.length;
  List<String> get dishNames => List.unmodifiable(_dishNames);

  /// Loads every recipe of the meal and MERGES their ingredients into one shopping
  /// list: an item needed by several dishes appears once, with the combined quantity
  /// and a note of which dishes need it (and therefore only one photo).
  Future<void> load(List<String> recipeIds) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    // Use the stoves/servings the user picked on the setup screen instead of hard-coded defaults.
    _stoveCount = await _storage.stoveCount;
    _serves = await _storage.servingCount;

    // 1. Load every recipe and merge their ingredient lists.
    final result =
        await _ingredientService.getRecipesWithIngredients(recipeIds);

    switch (result) {
      case Success(data: final recipes):
        _dishNames = recipes.map((r) => r.dishName).toList();
        pending = _mergeIngredients(recipes);
        confirmed = [];
        _fetchPhotos();
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

  /// Adds every dish of the meal to the already-created session, which kicks off scheduling.
  /// Called when the user has confirmed every ingredient and is transitioning to the cooking screen.
  Future<bool> startCooking() async {
    if (sessionId == null || _dishNames.isEmpty) return false;
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    for (final dishName in _dishNames) {
      final res =
          await _api.post(ApiConstants.sessionDishes(sessionId!), body: {
        'dishName': dishName,
        'servesRequested': _serves < 1 ? 1 : _serves,
      });

      switch (res) {
        case Success():
          break;
        case Failure(message: final m):
          isLoading = false;
          errorMessage = m;
          notifyListeners();
          return false;
      }
    }

    isLoading = false;
    notifyListeners();
    return true;
  }

  /// Collapses the meal's ingredient lists into one card per unique item+unit:
  /// quantities are summed and every dish that needs it is recorded on the card.
  List<IngredientModel> _mergeIngredients(List<RecipeModel> recipes) {
    final merged = <String, IngredientModel>{};

    for (final recipe in recipes) {
      for (final ingredient in recipe.ingredients) {
        final nameKey = ingredient.name.trim().toLowerCase();
        if (nameKey.isEmpty) continue;
        final unitKey = ingredient.unit.trim().toLowerCase();
        final key = '$nameKey|$unitKey';

        final existing = merged[key];
        if (existing == null) {
          var newId = ingredient.id.trim();
          if (newId.isEmpty || merged.values.any((m) => m.id == newId)) {
            newId =
                'item_${merged.length}_${key.replaceAll(RegExp(r'[^a-z0-9]+'), '_')}';
          }
          merged[key] = IngredientModel(
            id: newId,
            name: ingredient.name.trim(),
            quantityPerServe: ingredient.quantityPerServe,
            unit: ingredient.unit,
            dishNames: [recipe.dishName],
          );
        } else {
          existing.quantityPerServe = double.parse(
              (existing.quantityPerServe + ingredient.quantityPerServe)
                  .toStringAsFixed(3));
          if (!existing.dishNames.contains(recipe.dishName)) {
            existing.dishNames.add(recipe.dishName);
          }
        }
      }
    }

    return merged.values.toList();
  }

  /// One photo per unique ingredient name - merged duplicates share the same image.
  void _fetchPhotos() {
    final requested = <String>{};
    for (final item in pending) {
      final nameKey = item.name.trim().toLowerCase();
      if (!requested.add(nameKey)) continue;

      _unsplash.fetchImageUrl(item.name).then((url) {
        if (url == null) return;
        for (final other in [...pending, ...confirmed]) {
          if (other.name.trim().toLowerCase() == nameKey) {
            other.imageUrl = url;
          }
        }
        notifyListeners();
      });
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
        markConfirmedByNames(_ingredientNamesFromMessage(msg, data));
      } else if (type == 'item_confirmed') {
        final name =
            data?['itemName']?.toString() ?? msg['itemName']?.toString();
        if (name != null) markConfirmedByName(name);
      } else if (type == 'item_missing') {
        final name =
            data?['itemName']?.toString() ?? msg['itemName']?.toString();
        if (name != null && !missingItems.contains(name)) {
          missingItems.add(name);
          notifyListeners();
        }
      } else if (command == 'REMOVE') {
        markConfirmedByNames(_ingredientNamesFromMessage(msg, data));
      }
    });
  }

  List<String> _ingredientNamesFromMessage(
    Map<String, dynamic> message,
    Map<String, dynamic>? data,
  ) {
    final rawNames = data?['ingredientNames'] ?? message['ingredientNames'];
    if (rawNames is List) {
      return rawNames
          .map((name) => name.toString().trim())
          .where((name) => name.isNotEmpty)
          .toList();
    }

    final singleName = data?['ingredientName']?.toString() ??
        message['ingredientName']?.toString();
    if (singleName == null || singleName.trim().isEmpty) return const [];

    return singleName
        .split(RegExp(r'\s*(?:,|\band\b|&)\s*', caseSensitive: false))
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
  }

  void markConfirmedByNames(Iterable<String> names) {
    final requestedNames = names
        .map((name) => name.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toList();
    if (requestedNames.isEmpty || pending.isEmpty) return;

    final usedIndices = <int>{};

    for (var i = 0; i < requestedNames.length; i++) {
      final available = <int, int>{};
      for (var index = 0; index < pending.length; index++) {
        if (usedIndices.contains(index)) continue;
        final score = _nameMatchScore(pending[index].name, requestedNames[i]);
        if (score != null) available[index] = score;
      }
      if (available.isEmpty) continue;

      final bestScore = available.values.reduce((a, b) => a < b ? a : b);
      final bestIndices = available.entries
          .where((entry) => entry.value == bestScore)
          .map((entry) => entry.key)
          .toList();
      if (bestIndices.length == 1) {
        usedIndices.add(bestIndices.single);
      }
    }

    if (usedIndices.isEmpty) return;
    final matchedItems = usedIndices.toList()..sort();
    final itemsToMove = matchedItems.map((index) => pending[index]).toSet();
    for (final item in itemsToMove) {
      item.isConfirmedAvailable = true;
      confirmed.add(item);
    }
    pending.removeWhere(itemsToMove.contains);
    notifyListeners();
  }

  void markConfirmedByName(String name) {
    markConfirmedByNames([name]);
  }

  int? _nameMatchScore(String item, String query) {
    String singular(String s) {
      if (s.endsWith('ies') && s.length > 3) {
        return '${s.substring(0, s.length - 3)}y';
      }
      if (s.endsWith('oes') && s.length > 4) {
        return s.substring(0, s.length - 2);
      }
      if (s.endsWith('es') &&
          s.length > 4 &&
          (s.endsWith('ses') ||
              s.endsWith('xes') ||
              s.endsWith('zes') ||
              s.endsWith('ches') ||
              s.endsWith('shes'))) {
        return s.substring(0, s.length - 2);
      }
      if (s.endsWith('s') && !s.endsWith('ss') && s.length > 3) {
        return s.substring(0, s.length - 1);
      }
      return s;
    }

    List<String> normalize(String value) => value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map(singular)
        .toList();

    final itemWords = normalize(item);
    final queryWords = normalize(query);
    if (itemWords.isEmpty || queryWords.isEmpty) return null;
    if (itemWords.join(' ') == queryWords.join(' ')) return 0;
    if (queryWords.length == 1 && itemWords.contains(queryWords.single)) {
      return 1;
    }

    var totalDistance = 0;
    for (final queryWord in queryWords) {
      int? bestDistance;
      for (final itemWord in itemWords) {
        final distance = _editDistance(queryWord, itemWord);
        final maxDistance = queryWord.length >= 8 ? 2 : 1;
        if ((queryWord.length < 4 && queryWord != itemWord) ||
            distance > maxDistance) {
          continue;
        }
        if (bestDistance == null || distance < bestDistance) {
          bestDistance = distance;
        }
      }
      if (bestDistance == null) return null;
      totalDistance += bestDistance;
    }
    return 10 + totalDistance;
  }

  int _editDistance(String left, String right) {
    var previous = List<int>.generate(right.length + 1, (index) => index);
    for (var i = 1; i <= left.length; i++) {
      final current = List<int>.filled(right.length + 1, 0);
      current[0] = i;
      for (var j = 1; j <= right.length; j++) {
        final substitution =
            previous[j - 1] + (left[i - 1] == right[j - 1] ? 0 : 1);
        current[j] = [
          previous[j] + 1,
          current[j - 1] + 1,
          substitution,
        ].reduce((a, b) => a < b ? a : b);
      }
      previous = current;
    }
    return previous[right.length];
  }

  /// Manually remove an ingredient from the pending grid by ID
  void removeIngredient(String id) {
    pending.removeWhere((i) => i.id == id);
    notifyListeners();
  }

  bool get isDoneConfirming => pending.isEmpty;

  /// Names still on the checklist - read out when the assistant is asked what's remaining.
  List<String> get remainingNames => pending.map((i) => i.name).toList();

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

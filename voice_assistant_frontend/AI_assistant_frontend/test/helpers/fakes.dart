import 'dart:async';
import 'dart:convert';

import 'package:ai_assistant_frontend/core/network/websocket_service.dart';
import 'package:ai_assistant_frontend/core/utils/result.dart';
import 'package:ai_assistant_frontend/models/recipe_model.dart';
import 'package:ai_assistant_frontend/services/ai_service.dart';
import 'package:ai_assistant_frontend/services/ingredient_service.dart';
import 'package:ai_assistant_frontend/services/recipe_service.dart';
import 'package:ai_assistant_frontend/services/unsplash_service.dart';
import 'package:ai_assistant_frontend/services/voice_service.dart';
import 'package:http/http.dart' as http;

import 'fixtures.dart';

http.Response jsonResponse(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// A WebSocket stand-in. Extends the real service so ViewModels can accept
/// it through the same factory type, but never touches the network.
class FakeWebSocket extends AppWebSocketService {
  FakeWebSocket() : super(url: 'wss://test.local/ws');

  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  final List<dynamic> sent = [];
  int connectCalls = 0;
  int closeCalls = 0;
  int disposeCalls = 0;
  bool connected = false;

  @override
  Stream<Map<String, dynamic>> get messages => _controller.stream;

  @override
  void connect() {
    connectCalls++;
    connected = true;
  }

  @override
  void send(dynamic payload) {
    sent.add(payload);
  }

  @override
  void close() {
    closeCalls++;
    connected = false;
  }

  @override
  void dispose() {
    disposeCalls++;
    close();
    _controller.close();
  }

  void emit(Map<String, dynamic> message) => _controller.add(message);
}

class FakeVoiceEngine implements VoiceEngine {
  bool permissionGranted = true;
  bool sttReady = true;
  bool listening = false;
  bool disposed = false;

  final List<String> spoken = [];
  final List<String?> audioPayloads = [];
  int startCalls = 0;
  int stopCalls = 0;
  int initTtsCalls = 0;
  int micPermissionCalls = 0;

  void Function(String text, bool isFinal)? onResult;
  void Function(String status)? onStatus;

  @override
  Future<bool> requestMicPermission() async {
    micPermissionCalls++;
    return permissionGranted;
  }

  @override
  Future<bool> initSpeech({void Function(String status)? onStatus}) async {
    this.onStatus = onStatus;
    return sttReady;
  }

  @override
  Future<void> initTts() async {
    initTtsCalls++;
  }

  @override
  Future<void> startListening({
    required void Function(String text, bool isFinal) onResult,
  }) async {
    startCalls++;
    listening = true;
    this.onResult = onResult;
  }

  @override
  Future<void> stopListening() async {
    stopCalls++;
    listening = false;
  }

  @override
  bool get isListening => listening;

  @override
  Future<void> speakLocally(String text) async {
    spoken.add(text);
  }

  @override
  Future<void> synthesizeAndPlay(String text, {String? audioBase64}) async {
    spoken.add(text);
    audioPayloads.add(audioBase64);
  }

  @override
  void dispose() {
    disposed = true;
    listening = false;
  }

  void emitResult(String text, {bool isFinal = false}) =>
      onResult?.call(text, isFinal);

  void emitStatus(String status) => onStatus?.call(status);
}

class FakeAiService extends AiService {
  Result<VoiceCommandResult> commandResult =
      Success(VoiceCommandResult(command: 'UNKNOWN'));
  Result<String> helpResult = const Success('You can ask me to remove items.');
  Result<String> suggestionResult = const Success('');
  Result<List<CommandExample>> commandsResult = Success(const []);

  final List<String> classifiedTranscripts = [];
  final List<String> helpQuestions = [];
  final List<String> suggestions = [];

  @override
  Future<Result<VoiceCommandResult>> classifyCommand(String transcript) async {
    classifiedTranscripts.add(transcript);
    return commandResult;
  }

  @override
  Future<Result<String>> askHelp(String question) async {
    helpQuestions.add(question);
    return helpResult;
  }

  @override
  Future<Result<List<CommandExample>>> getHelpCommands() async =>
      commandsResult;

  @override
  Future<Result<String>> suggestDishName(String partialName) async {
    suggestions.add(partialName);
    return suggestionResult;
  }
}

class FakeRecipeService extends RecipeService {
  Result<List<RecipeModel>> listResult = Success(sampleRecipes());
  Result<RecipeModel> byIdResult = Success(sampleRecipe());
  Result<RecipeModel> generateResult = Success(sampleRecipe());
  Result<RecipeModel> findOrGenerateResult = Success(sampleRecipe());

  Duration listDelay = Duration.zero;
  Duration generateDelay = Duration.zero;

  int listCalls = 0;
  int byIdCalls = 0;
  int generateCalls = 0;
  final List<String> generatedDishNames = [];
  String? lastSearch;
  RecipeSortOption? lastSort;
  String? lastGenerateDish;
  String? lastRequestedId;

  @override
  Future<Result<List<RecipeModel>>> getRecipes({
    String? search,
    RecipeSortOption? sort,
  }) async {
    listCalls++;
    lastSearch = search;
    lastSort = sort;
    if (listDelay > Duration.zero) await Future<void>.delayed(listDelay);
    return listResult;
  }

  @override
  Future<Result<RecipeModel>> getRecipeById(String id) async {
    byIdCalls++;
    lastRequestedId = id;
    return byIdResult;
  }

  @override
  Future<Result<RecipeModel>> generateRecipe({required String dishName}) async {
    generateCalls++;
    lastGenerateDish = dishName;
    generatedDishNames.add(dishName);
    if (generateDelay > Duration.zero) {
      await Future<void>.delayed(generateDelay);
    }
    return generateResult;
  }

  @override
  Future<Result<RecipeModel>> findOrGenerateRecipe({
    required String dishName,
  }) async {
    lastGenerateDish = dishName;
    return findOrGenerateResult;
  }
}

class FakeIngredientService extends IngredientService {
  Result<RecipeModel> result =
      Success(recipeWithIngredients([]));
  int calls = 0;
  String? lastRecipeId;

  @override
  Future<Result<RecipeModel>> getRecipeWithIngredients(String recipeId) async {
    calls++;
    lastRecipeId = recipeId;
    return result;
  }
}

class FakeUnsplashService extends UnsplashService {
  String? url = 'https://images.example.test/item.jpg';
  final List<String> queries = [];

  @override
  Future<String?> fetchImageUrl(String query) async {
    queries.add(query);
    return url;
  }
}

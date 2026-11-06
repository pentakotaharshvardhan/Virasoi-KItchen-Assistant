import '../core/constants/api_constants.dart';
import '../core/network/api_client.dart';
import '../core/utils/result.dart';

class VoiceCommandResult {
  final String command;
  final int? stoveIndex;
  final String? dishName;
  final String? ingredientName;
  final int? timerSeconds;
  final String? helpResponse;

  VoiceCommandResult({
    required this.command,
    this.stoveIndex,
    this.dishName,
    this.ingredientName,
    this.timerSeconds,
    this.helpResponse,
  });

  factory VoiceCommandResult.fromJson(Map<String, dynamic> json) => VoiceCommandResult(
        command: json['command'].toString(),
        stoveIndex: json['stoveIndex'] as int?,
        dishName: json['dishName']?.toString(),
        ingredientName: json['ingredientName']?.toString(),
        timerSeconds: json['timerSeconds'] as int?,
        helpResponse: json['helpResponse']?.toString(),
      );
}

class CommandExample {
  final String phrase;
  final String command;
  final String note;

  CommandExample({required this.phrase, required this.command, required this.note});

  factory CommandExample.fromJson(Map<String, dynamic> json) => CommandExample(
        phrase: json['phrase'].toString(),
        command: json['command'].toString(),
        note: json['note'].toString(),
      );
}

class AiService {
  AiService({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  /// Given a raw transcript, returns structured command and params.
  Future<Result<VoiceCommandResult>> classifyCommand(String transcript) async {
    final res = await _api.post(ApiConstants.aiCommand, body: {
      'transcript': transcript,
    });
    print("DEBUG: REST Command Classification Response -> ${res is Success ? res.data : 'FAILED'}");
    return switch (res) {
      Success(data: final data) => Success(VoiceCommandResult.fromJson(data as Map<String, dynamic>)),
      Failure(message: final m) => Failure(m),
    };
  }

  /// Answers a general question about the app.
  Future<Result<String>> askHelp(String question) async {
    final res = await _api.post(ApiConstants.aiHelp, body: {
      'question': question,
    });
    print("DEBUG: REST AI Help Response -> ${res is Success ? res.data : 'FAILED'}");
    return switch (res) {
      Success(data: final data) => Success((data as Map<String, dynamic>)['answer'].toString()),
      Failure(message: final m) => Failure(m),
    };
  }

  /// Returns the canonical list of example phrases.
  Future<Result<List<CommandExample>>> getHelpCommands() async {
    final res = await _api.get(ApiConstants.aiHelpCommands);
    return switch (res) {
      Success(data: final data) => Success((data as List).map((e) => CommandExample.fromJson(e)).toList()),
      Failure(message: final m) => Failure(m),
    };
  }

  /// Corrects spelling or suggests dish names as the user types.
  Future<Result<String>> suggestDishName(String partialName) async {
    // Reusing the classify logic or a specialized prompt if the backend had one.
    // Given the request, we can use find-or-generate or a lightweight classify call.
    // For now, let's assume we can use a dedicated prompt if needed, 
    // but I'll use the existing search/generate pattern.
    final res = await _api.get('/api/recipes/search', query: {'query': partialName});
    return switch (res) {
      Success(data: final data) => Success((data as List).isEmpty ? partialName : (data.first as Map)['dishName'].toString()),
      Failure(message: final m) => Failure(m),
    };
  }
}

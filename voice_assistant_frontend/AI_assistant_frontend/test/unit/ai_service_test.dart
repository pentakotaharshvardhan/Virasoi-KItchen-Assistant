import 'dart:convert';

import 'package:ai_assistant_frontend/core/network/api_client.dart';
import 'package:ai_assistant_frontend/core/utils/result.dart';
import 'package:ai_assistant_frontend/services/ai_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import '../helpers/fakes.dart';

void main() {
  group('VoiceCommandResult (action type identification)', () {
    test('parses REMOVE with its ingredient', () {
      final result = VoiceCommandResult.fromJson({
        'command': 'REMOVE',
        'ingredientName': 'Onion',
      });

      expect(result.command, 'REMOVE');
      expect(result.ingredientName, 'Onion');
      expect(result.stoveIndex, isNull);
      expect(result.timerSeconds, isNull);
    });

    test('parses ADD with a dish name', () {
      final result = VoiceCommandResult.fromJson({
        'command': 'ADD',
        'dishName': 'Dal Makhani',
        'stoveIndex': 1,
      });

      expect(result.command, 'ADD');
      expect(result.dishName, 'Dal Makhani');
      expect(result.stoveIndex, 1);
    });

    test('parses HELP with its response', () {
      final result = VoiceCommandResult.fromJson({
        'command': 'HELP',
        'helpResponse': 'Say "remove onion" to clear it.',
      });

      expect(result.command, 'HELP');
      expect(result.helpResponse, 'Say "remove onion" to clear it.');
    });

    test('parses timer commands', () {
      final result = VoiceCommandResult.fromJson({
        'command': 'START_TIMER',
        'timerSeconds': 300,
        'stoveIndex': 2,
      });

      expect(result.command, 'START_TIMER');
      expect(result.timerSeconds, 300);
      expect(result.stoveIndex, 2);
    });

    test('keeps UNKNOWN and other command types intact', () {
      for (final command in ['UNKNOWN', 'START', 'STOP', 'NEXT_STEP', 'COMPLETE']) {
        expect(VoiceCommandResult.fromJson({'command': command}).command, command);
      }
    });
  });

  group('CommandExample', () {
    test('parses phrase, command and note', () {
      final example = CommandExample.fromJson({
        'phrase': 'remove onions',
        'command': 'REMOVE',
        'note': 'Removes an ingredient from the list',
      });

      expect(example.phrase, 'remove onions');
      expect(example.command, 'REMOVE');
      expect(example.note, contains('Removes'));
    });
  });

  group('AiService', () {
    test('classifyCommand posts the transcript and parses the command', () async {
      late Map<String, dynamic> body;
      final api = ApiClient.withClient(MockClient((request) async {
        expect(request.url.path, '/api/ai/command');
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return jsonResponse({
          'command': 'REMOVE',
          'ingredientName': 'Paneer',
        });
      }));

      final result = await AiService(api: api).classifyCommand('remove paneer');

      expect(body, {'transcript': 'remove paneer'});
      final command = (result as Success<VoiceCommandResult>).data;
      expect(command.command, 'REMOVE');
      expect(command.ingredientName, 'Paneer');
    });

    test('classifyCommand propagates a backend failure', () async {
      final api = ApiClient.withClient(
        MockClient((_) async => jsonResponse({'message': 'AI unavailable'}, status: 503)),
      );

      final result = await AiService(api: api).classifyCommand('hello');

      expect((result as Failure<VoiceCommandResult>).message, 'AI unavailable');
    });

    test('askHelp returns the answer text', () async {
      final api = ApiClient.withClient(MockClient((request) async {
        expect(request.url.path, '/api/ai/help');
        return jsonResponse({'answer': 'Ask me to remove ingredients.'});
      }));

      final result = await AiService(api: api).askHelp('What can you do?');

      expect((result as Success<String>).data, 'Ask me to remove ingredients.');
    });

    test('getHelpCommands parses a list of examples', () async {
      final api = ApiClient.withClient(MockClient((_) async => jsonResponse([
            {'phrase': 'remove onion', 'command': 'REMOVE', 'note': 'n1'},
            {'phrase': 'what is next', 'command': 'HELP', 'note': 'n2'},
          ])));

      final result = await AiService(api: api).getHelpCommands();

      final examples = (result as Success<List<CommandExample>>).data;
      expect(examples.length, 2);
      expect(examples.first.command, 'REMOVE');
    });

    test('suggestDishName returns the input when search finds nothing', () async {
      final api = ApiClient.withClient(MockClient((request) async {
        expect(request.url.path, '/api/recipes/search');
        expect(request.url.queryParameters['query'], 'paneer b');
        return jsonResponse([]);
      }));

      final result = await AiService(api: api).suggestDishName('paneer b');

      expect((result as Success<String>).data, 'paneer b');
    });

    test('suggestDishName returns the first dish name when matches exist', () async {
      final api = ApiClient.withClient(MockClient(
        (_) async => jsonResponse([
          {'dishName': 'Paneer Butter Masala'},
        ]),
      ));

      final result = await AiService(api: api).suggestDishName('paneer');

      expect((result as Success<String>).data, 'Paneer Butter Masala');
    });
  });
}

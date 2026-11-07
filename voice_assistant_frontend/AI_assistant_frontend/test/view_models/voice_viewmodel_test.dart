import 'package:ai_assistant_frontend/core/utils/result.dart';
import 'package:ai_assistant_frontend/core/utils/secure_storage.dart';
import 'package:ai_assistant_frontend/models/chat_message_model.dart';
import 'package:ai_assistant_frontend/services/voice_service.dart';
import 'package:ai_assistant_frontend/view_models/voice_viewmodel.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

void main() {
  late FakeVoiceEngine voice;
  late FakeAiService ai;
  late FakeWebSocket ws;
  late SecureStorage storage;

  setUp(() {
    voice = FakeVoiceEngine();
    ai = FakeAiService();
    ws = FakeWebSocket();
    storage = SecureStorage.inMemory();
  });

  VoiceViewModel buildViewModel() => VoiceViewModel(
        voice: voice,
        aiService: ai,
        storage: storage,
        wsFactory: (url, token) => ws,
      );

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  group('initialisation', () {
    test('requests mic, inits TTS, connects the socket and listens', () async {
      await storage.saveSession(accessToken: 'jwt');
      final vm = buildViewModel();

      await vm.init('sess-42');

      expect(voice.micPermissionCalls, 1);
      expect(voice.initTtsCalls, 1);
      expect(voice.startCalls, greaterThanOrEqualTo(1));
      expect(ws.connected, isTrue);
      expect(vm.sessionId, 'sess-42');
      expect(vm.state, VoiceState.listening);
    });

    test('generates a session id when none is supplied', () async {
      final vm = buildViewModel();

      await vm.init(null);

      expect(vm.sessionId, isNotNull);
      expect(vm.sessionId, isNotEmpty);
    });

    test('keeps help mode in state', () async {
      final vm = buildViewModel();

      await vm.init('s', helpMode: true);

      expect(vm.isHelpMode, isTrue);
    });
  });

  group('speech to text', () {
    test('partial results update the live transcript without sending', () async {
      final vm = buildViewModel();
      await vm.init('s');

      voice.emitResult('I have onions');

      expect(vm.liveTranscript, 'I have onions');
      expect(ws.sent, isEmpty);
      expect(vm.state, VoiceState.listening);
    });

    test('a final result is sent over the socket and becomes a user message', () async {
      final vm = buildViewModel();
      await vm.init('s');

      voice.emitResult('remove onion', isFinal: true);
      await flush();

      final payload = ws.sent.single as Map<String, dynamic>;
      expect(payload['type'], 'user_text');
      expect(payload['sessionId'], 's');
      expect(payload['text'], 'remove onion');
      expect(payload['transcript'], 'remove onion');
      expect(vm.liveTranscript, '');
      expect(vm.transcript.single.text, 'remove onion');
      expect(vm.transcript.single.sender, ChatSender.user);
      expect(vm.state, VoiceState.thinking);
    });

    test('sends after 20 seconds of unchanged partial text', () {
      fakeAsync((async) {
        final vm = buildViewModel();
        vm.init('s');
        async.flushMicrotasks();

        voice.emitResult('I have onions');
        async.elapse(const Duration(seconds: 19));
        expect(ws.sent, isEmpty);

        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(ws.sent, hasLength(1));
      });
    });

    test('changing the partial text restarts the 20 second window', () {
      fakeAsync((async) {
        final vm = buildViewModel();
        vm.init('s');
        async.flushMicrotasks();

        voice.emitResult('I have');
        async.elapse(const Duration(seconds: 5));
        voice.emitResult('I have onions');
        async.elapse(const Duration(seconds: 19));
        expect(ws.sent, isEmpty);

        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(ws.sent, hasLength(1));
      });
    });

    test('final recognition segments are retained in the submitted transcript',
        () {
      fakeAsync((async) {
        final vm = buildViewModel();
        vm.init('s');
        async.flushMicrotasks();

        voice.emitResult('remove onions');
        voice.emitResult('and tomatoes', isFinal: true);

        async.flushMicrotasks();
        final payload = ws.sent.single as Map<String, dynamic>;
        expect(payload['text'], 'remove onions and tomatoes');
      });
    });

    test('silence never triggers a send', () {
      fakeAsync((async) {
        final vm = buildViewModel();
        vm.init('s');
        async.flushMicrotasks();

        voice.emitResult('');
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();

        expect(ws.sent, isEmpty);
      });
    });

    test('restarts listening when the platform stops STT on silence', () async {
      final vm = buildViewModel();
      await vm.init('s');
      final startsBefore = voice.startCalls;

      voice.emitStatus('done');
      await flush();

      expect(voice.startCalls, startsBefore + 1);
    });

    test('restarts listening without losing pending transcript text', () async {
      final vm = buildViewModel();
      await vm.init('s');
      voice.emitResult('half a sentence');
      final startsBefore = voice.startCalls;

      voice.emitStatus('notListening');
      await flush();

      expect(voice.startCalls, startsBefore + 1);
      expect(vm.liveTranscript, 'half a sentence');
    });
  });

  group('help mode', () {
    test('asks the REST help endpoint instead of the socket', () async {
      ai.helpResult = const Success('Say "remove onion" to clear it.');
      final vm = buildViewModel();
      await vm.init('s', helpMode: true);

      voice.emitResult('how do I remove onions', isFinal: true);
      await flush();
      await flush();

      expect(ai.helpQuestions, ['how do I remove onions']);
      expect(ws.sent, isEmpty);
      expect(vm.transcript.last.sender, ChatSender.assistant);
      expect(vm.transcript.last.text, 'Say "remove onion" to clear it.');
      expect(voice.spoken, contains('Say "remove onion" to clear it.'));
    });

    test('speaks the help failure message', () async {
      ai.helpResult = const Failure('AI is down');
      final vm = buildViewModel();
      await vm.init('s', helpMode: true);

      voice.emitResult('help me', isFinal: true);
      await flush();
      await flush();

      expect(vm.transcript.last.text, 'AI is down');
    });
  });

  group('AI responses from the server', () {
    test('ignores the connected handshake', () async {
      final vm = buildViewModel();
      await vm.init('s');

      ws.emit({'type': 'connected'});
      await flush();

      expect(vm.transcript, isEmpty);
    });

    test('forwards multi-item removal broadcasts to the ingredient checklist',
        () async {
      final vm = buildViewModel();
      final removed = <String>[];
      vm.onIngredientsRemoved = removed.addAll;
      await vm.init('s');

      ws.emit({
        'type': 'remove_ingredient',
        'data': {
          'ingredientNames': ['onion', 'tomato']
        },
      });
      await flush();

      expect(removed, ['onion', 'tomato']);
    });

    test('speaks a prompt message', () async {
      final vm = buildViewModel();
      await vm.init('s');

      ws.emit({'type': 'prompt', 'message': 'Add the paneer now.'});
      await flush();

      expect(vm.transcript.last.text, 'Add the paneer now.');
      expect(vm.transcript.last.sender, ChatSender.assistant);
      expect(voice.spoken, contains('Add the paneer now.'));
    });

    test('forwards base64 audio to the voice engine', () async {
      final vm = buildViewModel();
      await vm.init('s');

      ws.emit({
        'type': 'prompt',
        'message': 'Audio reply',
        'messageAudioBase64': 'QUJD',
      });
      await flush();

      expect(voice.audioPayloads, contains('QUJD'));
    });

    test('speaks a plain text reply', () async {
      final vm = buildViewModel();
      await vm.init('s');

      ws.emit({'type': 'text', 'text': 'Timer started.'});
      await flush();

      expect(vm.transcript.last.text, 'Timer started.');
    });

    test('reads text from a data wrapper', () async {
      final vm = buildViewModel();
      await vm.init('s');

      ws.emit({
        'type': 'text',
        'data': {'text': 'Wrapped reply'},
      });
      await flush();

      expect(vm.transcript.last.text, 'Wrapped reply');
    });

    test('does not duplicate the same consecutive assistant reply', () async {
      final vm = buildViewModel();
      await vm.init('s');

      ws.emit({'type': 'text', 'text': 'Same reply'});
      await flush();
      ws.emit({'type': 'text', 'text': 'Same reply'});
      await flush();

      expect(
        vm.transcript.where((m) => m.text == 'Same reply').length,
        1,
      );
    });

    test('speaks error messages', () async {
      final vm = buildViewModel();
      await vm.init('s');

      ws.emit({'type': 'error', 'message': 'Network broke'});
      await flush();

      expect(vm.transcript.last.text, 'Network broke');
    });

    test('suppresses the raw "Unknown action" backend error', () async {
      final vm = buildViewModel();
      await vm.init('s');

      ws.emit({'type': 'error', 'message': 'Unknown action'});
      await flush();

      expect(vm.transcript, isEmpty);
    });

    test('maps an unknown-action text reply to a friendly sentence', () async {
      final vm = buildViewModel();
      await vm.init('s');

      ws.emit({'type': 'text', 'text': 'unknown action'});
      await flush();

      expect(
        vm.transcript.last.text,
        "I'm sorry, I didn't understand that command. Could you please say it differently?",
      );
    });

    test('REMOVE command speaks the custom server message', () async {
      final vm = buildViewModel();
      await vm.init('s');

      ws.emit({
        'command': 'REMOVE',
        'ingredientName': 'Onion',
        'message': 'Removed onion from your list.',
      });
      await flush();

      expect(vm.transcript.last.text, 'Removed onion from your list.');
    });

    test('REMOVE command falls back to a generated sentence', () async {
      final vm = buildViewModel();
      await vm.init('s');

      ws.emit({'command': 'REMOVE', 'ingredientName': 'Onion'});
      await flush();

      expect(vm.transcript.last.text, 'Okay, removing Onion from your list.');
    });

    test('HELP command speaks the help response', () async {
      final vm = buildViewModel();
      await vm.init('s');

      ws.emit({
        'command': 'HELP',
        'helpResponse': 'You can say remove onion.',
      });
      await flush();

      expect(vm.transcript.last.text, 'You can say remove onion.');
    });

    test('UNKNOWN command falls through to the text handler', () async {
      final vm = buildViewModel();
      await vm.init('s');

      ws.emit({'command': 'UNKNOWN', 'text': 'Anything else?'});
      await flush();

      expect(vm.transcript.last.text, 'Anything else?');
    });

    test('restarts listening after speaking completes', () async {
      final vm = buildViewModel();
      await vm.init('s');
      final startsBefore = voice.startCalls;

      ws.emit({'type': 'text', 'text': 'Done'});
      await flush();
      await flush();

      expect(vm.state, VoiceState.listening);
      expect(voice.startCalls, greaterThan(startsBefore));
      expect(voice.listening, isTrue);
    });
  });

  group('lifecycle', () {
    test('stopListening cancels the pending stability send', () {
      fakeAsync((async) {
        final vm = buildViewModel();
        vm.init('s');
        async.flushMicrotasks();

        voice.emitResult('remove onion');
        async.elapse(const Duration(seconds: 2));
        vm.stopListening();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 20));
        async.flushMicrotasks();

        expect(ws.sent, isEmpty);
        expect(vm.state, VoiceState.idle);
      });
    });

    test('dispose closes the socket and the voice engine', () async {
      final vm = buildViewModel();
      await vm.init('s');

      vm.dispose();

      expect(ws.disposeCalls, 1);
      expect(voice.disposed, isTrue);
    });
  });

  group('ready check', () {
    test('"yes" fires the onReady callback and stops asking', () async {
      final vm = buildViewModel();
      await vm.init('s');
      var readyCalls = 0;
      await vm.beginReadyCheck(onReady: () async {
        readyCalls++;
      });

      expect(vm.readyCheckActive, isTrue);
      expect(voice.spoken.last, contains('ready to start cooking'));

      // Let the announcement finish and the mic come back before answering.
      await flush();
      voice.emitResult('yes', isFinal: true);
      await flush();
      await flush();

      expect(readyCalls, 1);
      expect(vm.readyCheckActive, isFalse);
      expect(ws.sent, isEmpty, reason: 'the answer must never hit the backend');
    });

    test('"not yet" keeps the question open', () async {
      final vm = buildViewModel();
      await vm.init('s');
      var readyCalls = 0;
      await vm.beginReadyCheck(onReady: () async {
        readyCalls++;
      });

      await flush();
      voice.emitResult('not yet', isFinal: true);
      await flush();
      await flush();

      expect(readyCalls, 0);
      expect(vm.readyCheckActive, isTrue);
      expect(voice.spoken.last, contains('take your time'));
      expect(ws.sent, isEmpty);
    });

    test('an unclear answer re-asks the question', () async {
      final vm = buildViewModel();
      await vm.init('s');
      var readyCalls = 0;
      await vm.beginReadyCheck(onReady: () async {
        readyCalls++;
      });

      await flush();
      voice.emitResult('hmm', isFinal: true);
      await flush();
      await flush();

      expect(readyCalls, 0);
      expect(vm.readyCheckActive, isTrue);
      expect(voice.spoken.last, contains('yes or no'));
      expect(ws.sent, isEmpty);
    });
  });

  group('remaining items', () {
    test('backend request reads out the pending ingredient list', () async {
      final vm = buildViewModel();
      await vm.init('s');
      vm.onRemainingItemsRequest = () async => ['Onion', 'Tomato'];

      ws.emit({
        'type': 'remaining_items_request',
        'data': {'message': 'Which items are still on the list?'},
      });
      await flush();
      await flush();

      expect(voice.spoken.last, 'You still need: Onion, Tomato.');
      expect(vm.transcript.last.text, 'You still need: Onion, Tomato.');
    });

    test('an empty list is answered gracefully', () async {
      final vm = buildViewModel();
      await vm.init('s');
      vm.onRemainingItemsRequest = () async => [];

      ws.emit({
        'type': 'remaining_items_request',
        'data': {'message': 'x'}
      });
      await flush();
      await flush();

      expect(voice.spoken.last, contains('nothing is left'));
    });

    test('a missing callback still produces a spoken answer', () async {
      final vm = buildViewModel();
      await vm.init('s');

      ws.emit({
        'type': 'remaining_items_request',
        'data': {'message': 'x'}
      });
      await flush();
      await flush();

      expect(voice.spoken.last, contains('nothing is left'));
    });
  });

  group('session snapshots', () {
    test('a snapshot is stored for the steps panel and its message is spoken',
        () async {
      final vm = buildViewModel();
      await vm.init('s');

      ws.emit({
        'type': 'session_snapshot',
        'data': {
          'message': 'Chop the onions.',
          'dishes': [
            {
              'name': 'Soup',
              'totalSteps': 3,
              'completedSteps': 1,
              'status': 'RUNNING'
            },
          ],
        },
      });
      await flush();

      expect(vm.lastSnapshot, isNotNull);
      expect(vm.lastSnapshot!['message'], 'Chop the onions.');
      expect(
        (vm.lastSnapshot!['dishes'] as List).single['completedSteps'],
        1,
      );
      expect(voice.spoken.last, 'Chop the onions.');
    });

    test('init resets a stale snapshot from a previous session', () async {
      final vm = buildViewModel();
      await vm.init('s');
      ws.emit({
        'type': 'session_snapshot',
        'data': {'message': 'Old session.'},
      });
      await flush();
      expect(vm.lastSnapshot, isNotNull);

      await vm.init(null);
      expect(vm.lastSnapshot, isNull);
    });
  });

  group('typed input', () {
    test('sendTypedText goes through the same pipeline as speech', () async {
      final vm = buildViewModel();
      await vm.init('s');

      vm.sendTypedText('  next  ');
      await flush();

      final payload = ws.sent.single as Map<String, dynamic>;
      expect(payload['type'], 'user_text');
      expect(payload['text'], 'next');
      expect(vm.transcript.single.text, 'next');
      expect(vm.transcript.single.sender, ChatSender.user);
    });

    test('blank input is ignored', () async {
      final vm = buildViewModel();
      await vm.init('s');

      vm.sendTypedText('   ');

      expect(ws.sent, isEmpty);
      expect(vm.transcript, isEmpty);
    });
  });
}

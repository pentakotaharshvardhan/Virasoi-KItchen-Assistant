import 'dart:async';

import 'package:ai_assistant_frontend/core/utils/result.dart';
import 'package:ai_assistant_frontend/core/utils/secure_storage.dart';
import 'package:ai_assistant_frontend/models/chat_message_model.dart';
import 'package:ai_assistant_frontend/services/ai_service.dart';
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
    test('partial results update the live transcript without sending',
        () async {
      final vm = buildViewModel();
      await vm.init('s');

      voice.emitResult('I have onions');

      expect(vm.liveTranscript, 'I have onions');
      expect(ws.sent, isEmpty);
      expect(vm.state, VoiceState.listening);
    });

    test('a final result is sent after the 12-second listening window', () {
      fakeAsync((async) {
        final vm = buildViewModel();
        vm.init('s');
        async.flushMicrotasks();

        voice.emitResult('remove onion', isFinal: true);
        async.flushMicrotasks();
        expect(ws.sent, isEmpty);

        async.elapse(const Duration(seconds: 12));
        async.flushMicrotasks();

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
    });

    test('help opens the in-app helper without sending a cooking command', () {
      fakeAsync((async) {
        var helperOpened = 0;
        final vm = buildViewModel()
          ..onHelpRequested = () async {
            helperOpened++;
          };
        vm.init('sess-1');
        async.flushMicrotasks();

        voice.emitResult('help me', isFinal: true);
        async.elapse(const Duration(seconds: 12));
        async.flushMicrotasks();

        expect(helperOpened, 1);
        expect(ai.classifiedTranscripts, isEmpty);
        expect(ws.sent, isEmpty);
      });
    });

    test('sends the unified REST command result to the session handler', () {
      fakeAsync((async) {
        ai.commandResult = Success(VoiceCommandResult(
          command: 'REMOVE',
          ingredientName: 'Paneer',
          ingredientNames: const ['Paneer'],
        ));
        final vm = buildViewModel();
        vm.onAvailableIngredients = () async => ['Paneer', 'Tomato'];
        vm.init('sess-1');
        async.flushMicrotasks();

        voice.emitResult('remove panner', isFinal: true);
        async.elapse(const Duration(seconds: 12));
        async.flushMicrotasks();

        final payload = ws.sent.single as Map<String, dynamic>;
        expect(payload['type'], 'command_result');
        expect(payload['text'], 'remove panner');
        expect(
          (payload['result'] as Map<String, dynamic>)['ingredientNames'],
          ['Paneer'],
        );
        expect(ai.ingredientCandidates.single, ['Paneer', 'Tomato']);
      });
    });

    test('submits non-empty transcript after 12 seconds', () {
      fakeAsync((async) {
        final vm = buildViewModel();
        vm.init('s');
        async.flushMicrotasks();

        voice.emitResult('I have onions');
        async.elapse(const Duration(seconds: 11));
        expect(ws.sent, isEmpty);

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(ws.sent, hasLength(1));
      });
    });

    test('restarts a fresh 12-second window when no text was recognized', () {
      fakeAsync((async) {
        final vm = buildViewModel();
        vm.init('s');
        async.flushMicrotasks();

        final startsBefore = voice.startCalls;
        async.elapse(const Duration(seconds: 12));
        async.flushMicrotasks();

        expect(ws.sent, isEmpty);
        expect(voice.startCalls, startsBefore + 1);
        expect(vm.state, VoiceState.listening);
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

        async.elapse(const Duration(seconds: 12));
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
    test('asks the REST help endpoint instead of the socket', () {
      fakeAsync((async) {
        ai.helpResult = const Success('Say "remove onion" to clear it.');
        final vm = buildViewModel();
        vm.init('s', helpMode: true);
        async.flushMicrotasks();

        voice.emitResult('how do I remove onions', isFinal: true);
        async.elapse(const Duration(seconds: 12));
        async.flushMicrotasks();

        expect(ai.helpQuestions, ['how do I remove onions']);
        expect(ws.sent, isEmpty);
        expect(vm.transcript.last.sender, ChatSender.assistant);
        expect(vm.transcript.last.text, 'Say "remove onion" to clear it.');
        expect(voice.spoken, contains('Say "remove onion" to clear it.'));
      });
    });

    test('speaks the help failure message', () {
      fakeAsync((async) {
        ai.helpResult = const Failure('AI is down');
        final vm = buildViewModel();
        vm.init('s', helpMode: true);
        async.flushMicrotasks();

        voice.emitResult('help me', isFinal: true);
        async.elapse(const Duration(seconds: 12));
        async.flushMicrotasks();

        expect(vm.transcript.last.text, 'AI is down');
      });
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
    test('stopListening cancels the 12-second listen window', () {
      fakeAsync((async) {
        final vm = buildViewModel();
        vm.init('s');
        async.flushMicrotasks();

        voice.emitResult('remove onion');
        async.elapse(const Duration(seconds: 2));
        vm.stopListening();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 12));
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
    test('"yes" fires the onReady callback and stops asking', () {
      fakeAsync((async) {
        final vm = buildViewModel();
        vm.init('s');
        async.flushMicrotasks();
        var readyCalls = 0;
        vm.beginReadyCheck(onReady: () async {
          readyCalls++;
        });
        async.flushMicrotasks();

        expect(vm.readyCheckActive, isTrue);
        expect(voice.spoken.last, contains('ready to start cooking'));

        // Let the announcement finish and the mic come back before answering.
        async.flushMicrotasks();
        voice.emitResult('yes', isFinal: true);
        async.elapse(const Duration(seconds: 12));
        async.flushMicrotasks();

        expect(readyCalls, 1);
        expect(vm.readyCheckActive, isFalse);
        expect(ws.sent, isEmpty,
            reason: 'the answer must never hit the backend');
      });
    });

    test('"not yet" keeps the question open', () {
      fakeAsync((async) {
        final vm = buildViewModel();
        vm.init('s');
        async.flushMicrotasks();
        var readyCalls = 0;
        vm.beginReadyCheck(onReady: () async {
          readyCalls++;
        });
        async.flushMicrotasks();

        voice.emitResult('not yet', isFinal: true);
        async.elapse(const Duration(seconds: 12));
        async.flushMicrotasks();

        expect(readyCalls, 0);
        expect(vm.readyCheckActive, isTrue);
        expect(voice.spoken.last, contains('take your time'));
        expect(ws.sent, isEmpty);
      });
    });

    test('an unclear answer re-asks the question', () {
      fakeAsync((async) {
        final vm = buildViewModel();
        vm.init('s');
        async.flushMicrotasks();
        var readyCalls = 0;
        vm.beginReadyCheck(onReady: () async {
          readyCalls++;
        });
        async.flushMicrotasks();

        voice.emitResult('hmm', isFinal: true);
        async.elapse(const Duration(seconds: 12));
        async.flushMicrotasks();

        expect(readyCalls, 0);
        expect(vm.readyCheckActive, isTrue);
        expect(voice.spoken.last, contains('yes or no'));
        expect(ws.sent, isEmpty);
      });
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

    test('the final snapshot ends the voice pipeline after the goodbye', () async {
      final vm = buildViewModel();
      await vm.init('s');
      voice.playbackGate = Completer<void>();

      ws.emit({
        'type': 'session_snapshot',
        'data': {
          'message': '"Dal" is done! All dishes are done. Happy meal!',
          'sessionStatus': 'COMPLETED',
          'dishes': [
            {'name': 'Dal', 'status': 'COMPLETED'},
          ],
        },
      });
      await flush();

      expect(vm.mealComplete, isTrue);
      expect(voice.spoken.last, contains('Happy meal'));

      voice.playbackGate!.complete();
      voice.playbackGate = null;
      await flush();

      expect(voice.listening, isFalse,
          reason: 'the mic stays off once the meal is over');
      expect(vm.state, VoiceState.idle);

      await vm.startListening();
      expect(voice.listening, isFalse, reason: 'and nothing may restart it');
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

      vm.sendTypedText('  remove the onions  ');
      await flush();

      final payload = ws.sent.single as Map<String, dynamic>;
      expect(payload['type'], 'user_text');
      expect(payload['text'], 'remove the onions');
      expect(vm.transcript.single.text, 'remove the onions');
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

  group('keyword fast path', () {
    test('a bare control word skips the classifier entirely', () async {
      final vm = buildViewModel();
      await vm.init('s');

      vm.sendTypedText('  next.  ');
      await flush();

      final payload = ws.sent.single as Map<String, dynamic>;
      expect(payload['type'], 'command_result');
      expect(payload['text'], 'next.');
      expect(payload['result'], containsPair('command', 'NEXT'));
      expect(ai.classifiedTranscripts, isEmpty,
          reason: 'no classification round trip');
    });

    test('every control phrase maps to its backend command', () async {
      final vm = buildViewModel();
      await vm.init('s');

      const expected = {
        'done': 'NEXT',
        'wait': 'WAIT',
        'say that again': 'REPEAT',
        'stop': 'STOP',
        'help': 'HELP',
      };
      for (final entry in expected.entries) {
        ws.sent.clear();
        vm.sendTypedText(entry.key);
        await flush();

        final payload = ws.sent.single as Map<String, dynamic>;
        expect(payload['type'], 'command_result');
        expect(payload['result'], containsPair('command', entry.value));
      }
      expect(ai.classifiedTranscripts, isEmpty);
    });

    test('anything needing context still goes to the classifier', () async {
      final vm = buildViewModel();
      await vm.init('s');

      vm.sendTypedText('next after the onions brown');
      await flush();

      expect(ai.classifiedTranscripts, ['next after the onions brown']);
      final payload = ws.sent.single as Map<String, dynamic>;
      expect(payload['type'], 'user_text');
    });
  });

  group('recogniser failures', () {
    test('a deliberate stop is not mistaken for a timeout restart', () async {
      final vm = buildViewModel();
      await vm.init('s');
      final starts = voice.startCalls;

      await vm.stopListening();
      // The platform confirms our own stop - this used to trigger an immediate restart.
      voice.onStatus?.call('notListening');
      await flush();

      expect(voice.startCalls, starts);
      expect(vm.state, VoiceState.idle);
    });

    test('a speech timeout backs off instead of hot-restarting', () {
      fakeAsync((async) {
        final vm = buildViewModel();
        vm.init('s');
        async.flushMicrotasks();
        final starts = voice.startCalls;

        voice.emitError('error_speech_timeout', permanent: true);
        async.flushMicrotasks();
        expect(voice.startCalls, starts,
            reason: 'no instant restart into the same error');

        async.elapse(const Duration(milliseconds: 499));
        expect(voice.startCalls, starts);

        async.elapse(const Duration(milliseconds: 2));
        async.flushMicrotasks();
        expect(voice.startCalls, starts + 1);
        expect(vm.state, VoiceState.listening);
      });
    });

    test('consecutive failures increase the delay', () {
      fakeAsync((async) {
        final vm = buildViewModel();
        vm.init('s');
        async.flushMicrotasks();

        voice.emitError('error_speech_timeout', permanent: true);
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        expect(voice.startCalls, 2);

        // Second failure waits 1000ms, not 500ms.
        voice.emitError('error_speech_timeout', permanent: true);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 900));
        expect(voice.startCalls, 2, reason: 'backing off');
        async.elapse(const Duration(milliseconds: 110));
        async.flushMicrotasks();
        expect(voice.startCalls, 3);
      });
    });

    test('errors are ignored once the mic was deliberately stopped', () async {
      final vm = buildViewModel();
      await vm.init('s');
      final starts = voice.startCalls;

      await vm.stopListening();
      voice.emitError('error_speech_timeout', permanent: true);
      await flush();

      expect(voice.startCalls, starts);
      expect(vm.state, VoiceState.idle);
    });

    test('recognised speech clears the backoff', () {
      fakeAsync((async) {
        final vm = buildViewModel();
        vm.init('s');
        async.flushMicrotasks();

        voice.emitError('error_speech_timeout', permanent: true);
        async.flushMicrotasks();

        voice.emitResult('remove onion');
        async.flushMicrotasks();

        // Next failure is back to the shortest delay (500ms).
        voice.emitError('error_speech_timeout', permanent: true);
        async.flushMicrotasks();
        final starts = voice.startCalls;
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        expect(voice.startCalls, starts + 1);
      });
    });

    test('no restart is scheduled after the view model goes inactive', () {
      fakeAsync((async) {
        final vm = buildViewModel();
        vm.init('s');
        async.flushMicrotasks();
        final starts = voice.startCalls;

        voice.emitError('error_speech_timeout', permanent: true);
        async.flushMicrotasks();
        vm.pause();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(voice.startCalls, starts);
      });
    });
  });

  group('duplicate frames', () {
    int assistants(VoiceViewModel vm) =>
        vm.transcript.where((m) => m.sender == ChatSender.assistant).length;

    Map<String, dynamic> snapshot(String message, int seq,
            {bool replay = false}) =>
        {
          'type': 'session_snapshot',
          'data': {'message': message},
          'seq': seq,
          if (replay) 'replay': true,
        };

    test('a frame already handled is not spoken twice', () async {
      final vm = buildViewModel();
      await vm.init('s');

      ws.emit(snapshot('Stir the onions for two minutes', 1));
      await flush();
      expect(assistants(vm), 1);
      expect(voice.spoken.length, 1);

      ws.emit(snapshot('Stir the onions for two minutes', 1));
      await flush();
      expect(assistants(vm), 1, reason: 'duplicate frame must not bubble');
      expect(voice.spoken.length, 1,
          reason: 'duplicate frame must not re-speak');
    });

    test('the next frame in the sequence is still handled', () async {
      final vm = buildViewModel();
      await vm.init('s');

      ws.emit(snapshot('Stir the onions for two minutes', 1));
      await flush();
      ws.emit(snapshot('Now add the tomatoes', 2));
      await flush();

      expect(assistants(vm), 2);
      expect(voice.spoken.length, 2);
    });

    test('a second instruction waits for the first voice to finish', () async {
      final vm = buildViewModel();
      await vm.init('s');

      final gate = Completer<void>();
      voice.playbackGate = gate;

      ws.emit(snapshot('First instruction', 1));
      await flush();
      ws.emit(snapshot('Second instruction', 2));
      await flush();

      expect(assistants(vm), 1, reason: 'one message displayed at a time');
      expect(voice.spoken, ['First instruction'],
          reason: 'the second message must not talk over the first');

      gate.complete();
      voice.playbackGate = null;
      await flush();
      await flush();

      expect(assistants(vm), 2);
      expect(voice.spoken, ['First instruction', 'Second instruction']);
    });

    test('the same instruction on a NEW seq (double push) stays silent',
        () async {
      // Regression: SchedulerService.completeStep broadcast the snapshot to every socket and
      // the handler then echoed its own copy - identical text, ~250ms apart, different seq, so
      // the seq check above lets the second frame through and only the text guard can stop it.
      final vm = buildViewModel();
      await vm.init('s');

      ws.emit(snapshot('Heat the pan and saute the onions.', 1));
      await flush();
      expect(assistants(vm), 1);
      expect(voice.spoken.length, 1);

      ws.emit(snapshot('Heat the pan and saute the onions.', 2));
      await flush();

      expect(assistants(vm), 1,
          reason: 'a new seq must not double a repeated instruction');
      expect(voice.spoken.length, 1,
          reason: 'the player from the first copy is still running');
      expect(vm.lastSnapshot?['message'], 'Heat the pan and saute the onions.',
          reason: 'the second copy still updates the state');
    });

    test('a reconnect restarts the sequence so new frames are not dropped',
        () async {
      final vm = buildViewModel();
      await vm.init('s');

      ws.emit(snapshot('Stir the onions for two minutes', 5));
      await flush();
      expect(assistants(vm), 1);

      // Socket dropped and re-established - the server starts counting again.
      ws.emitConnected();
      ws.emit(snapshot('Now add the tomatoes', 1));
      await flush();

      expect(assistants(vm), 2,
          reason: 'post-reconnect frame must not be dropped');
    });

    test('a replay of the current instruction updates state without speaking',
        () {
      fakeAsync((async) {
        final vm = buildViewModel();
        vm.init('s');
        async.flushMicrotasks();

        ws.emit(snapshot('Stir the onions for two minutes', 1));
        async.flushMicrotasks();
        expect(voice.spoken.length, 1);

        // Well past the duplicate window: only the replay rule can keep this silent.
        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();
        ws.emit(snapshot('Stir the onions for two minutes', 2, replay: true));
        async.flushMicrotasks();

        expect(vm.lastSnapshot?['message'], 'Stir the onions for two minutes');
        expect(voice.spoken.length, 1, reason: 'replay must not re-speak');
        expect(assistants(vm), 1, reason: 'replay must not double the bubble');
      });
    });

    test('the same instruction twice inside a few seconds is only said once',
        () async {
      final vm = buildViewModel();
      await vm.init('s');

      vm.speakText('Ready for the next step?');
      await flush();
      vm.speakText('Ready for the next step?');
      await flush();

      expect(voice.spoken.length, 1);
      expect(assistants(vm), 1);
    });

    test('frames after pause are ignored', () async {
      final vm = buildViewModel();
      await vm.init('s');
      await vm.pause();

      ws.emit(snapshot('Stir the onions for two minutes', 1));
      await flush();

      expect(assistants(vm), 0);
      expect(voice.spoken, isEmpty);
    });
  });

  group('connection status', () {
    Iterable<Map<String, dynamic>> statusFrames() => ws.sent
        .whereType<Map<String, dynamic>>()
        .where((f) => f['type'] == 'status');

    test('the first connect does not ask the server for a snapshot', () async {
      final vm = buildViewModel();
      await vm.init('s');

      expect(vm.wsConnected, isTrue);
      expect(statusFrames(), isEmpty,
          reason: 'the screen drives the first status itself');
    });

    test('a drop is reported and the next connect re-syncs the session',
        () async {
      final vm = buildViewModel();
      await vm.init('s');

      ws.emitConnected(value: false);
      await flush();
      expect(vm.wsConnected, isFalse,
          reason: 'the screen must be able to say so');

      ws.emitConnected();
      await flush();

      expect(vm.wsConnected, isTrue);
      expect(statusFrames(), hasLength(1),
          reason:
              'after a drop the state missed while offline must be re-requested');
    });

    test('a denied microphone is surfaced to the screen', () async {
      voice.permissionGranted = false;
      final vm = buildViewModel();

      await vm.init('s');

      expect(vm.micPermissionDenied, isTrue);
      expect(voice.startCalls, greaterThanOrEqualTo(1),
          reason: 'typing must keep working while the mic is off');
    });

    test('help mode never requests a session status', () async {
      final vm = buildViewModel();
      await vm.init('s', helpMode: true);

      ws.emitConnected(value: false);
      await flush();
      ws.emitConnected();
      await flush();

      expect(statusFrames(), isEmpty);
    });
  });
}

import 'package:ai_assistant_frontend/services/voice_state_machine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

void main() {
  late FakeVoiceEngine engine;
  late VoiceStateMachine machine;
  late List<VoiceTurnState> states;
  late List<String> results;
  late List<String> errors;
  var silences = 0;

  setUp(() {
    engine = FakeVoiceEngine();
    states = [];
    results = [];
    errors = [];
    silences = 0;
    machine = VoiceStateMachine(
      engine: engine,
      onStateChanged: states.add,
      onResult: (text, _) => results.add(text),
      onSilence: () => silences++,
      onError: (code, _) => errors.add(code),
    );
  });

  tearDown(() => machine.dispose());

  test('starting opens the microphone and reports listening', () async {
    await machine.start();

    expect(machine.state, VoiceTurnState.listening);
    expect(machine.isMicOpen, isTrue);
    expect(engine.startCalls, 1);
    expect(engine.listening, isTrue);
    expect(states, [VoiceTurnState.listening]);
  });

  test('the microphone is closed for the whole processing and speaking phases',
      () async {
    await machine.start();
    final turnId = await machine.beginProcessing();

    expect(machine.state, VoiceTurnState.processing);
    expect(machine.isMicOpen, isFalse);
    expect(engine.listening, isFalse);

    await machine.speak(turnId);
    expect(machine.state, VoiceTurnState.speaking);
    expect(machine.isMicOpen, isFalse);
    expect(engine.listening, isFalse);
  });

  test('recogniser results are dropped while the assistant speaks', () async {
    await machine.start();
    engine.emitResult('remove the onions', isFinal: true);
    expect(results, ['remove the onions']);

    final turnId = await machine.beginProcessing();
    await machine.speak(turnId);
    engine.emitResult('I heard myself talking', isFinal: true);

    expect(results, ['remove the onions'],
        reason: 'anti-echo gate: TTS must never become a user turn');
  });

  test('a stale playback completion does not reopen the microphone', () async {
    await machine.start();
    final first = await machine.beginProcessing();
    await machine.speak(first);

    // A second turn starts before the first playback reports completion.
    await machine.beginProcessing();
    await machine.finishSpeaking(first);

    expect(machine.state, VoiceTurnState.processing);
    expect(machine.isMicOpen, isFalse);

    // The duplicate callback for the already-finished turn is still ignored.
    await machine.finishSpeaking(first);
    expect(machine.isMicOpen, isFalse);
  });

  test('the matching playback completion reopens the microphone only once',
      () async {
    await machine.start();
    final turnId = await machine.beginProcessing();
    await machine.speak(turnId);

    await machine.finishSpeaking(turnId);
    expect(machine.state, VoiceTurnState.listening);
    expect(engine.startCalls, 2);

    await machine.finishSpeaking(turnId);
    expect(engine.startCalls, 2, reason: 'duplicate completion is a no-op');
  });

  test('a recogniser error keeps the mic closed until the caller retries',
      () async {
    await machine.start();
    machine.handleError('error_no_match', true);

    expect(errors, ['error_no_match']);
    await machine.noteError();
    expect(machine.state, VoiceTurnState.error);
    expect(machine.isMicOpen, isFalse);

    await machine.restartListening();
    expect(machine.state, VoiceTurnState.listening);
    expect(machine.isMicOpen, isTrue);
  });

  test('a platform stop is forwarded as silence while listening', () async {
    await machine.start();
    machine.handleStatus('done');

    expect(silences, 1);
  });

  test('a platform stop caused by our own close is not a user silence',
      () async {
    await machine.start();
    await machine.beginProcessing();
    machine.handleStatus('done');

    expect(silences, 0);
  });

  test('muting keeps the machine active so an announcement can still be spoken',
      () async {
    await machine.start();
    await machine.mute();

    expect(machine.state, VoiceTurnState.idle);
    expect(machine.isMicOpen, isFalse);
    expect(machine.isActive, isTrue);

    await machine.speak();
    expect(machine.state, VoiceTurnState.speaking);

    await machine.finishSpeaking();
    expect(machine.state, VoiceTurnState.listening);
    expect(machine.isMicOpen, isTrue);
  });

  test('pausing makes the machine inert until it is started again', () async {
    await machine.start();
    await machine.pause();

    expect(machine.isActive, isFalse);
    expect(machine.state, VoiceTurnState.idle);
    await machine.speak();
    expect(machine.state, VoiceTurnState.idle);

    await machine.start();
    expect(machine.state, VoiceTurnState.listening);
  });

  test('restarting with nothing said keeps exactly one microphone open', () async {
    await machine.start();
    final starts = engine.startCalls;

    await machine.restartListening();

    expect(engine.startCalls, starts + 1);
    expect(machine.isMicOpen, isTrue);
    expect(machine.state, VoiceTurnState.listening);
  });
}

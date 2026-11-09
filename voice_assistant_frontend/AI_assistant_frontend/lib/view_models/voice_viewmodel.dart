import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/api_constants.dart';
import '../core/network/websocket_service.dart';
import '../core/utils/result.dart';
import '../core/utils/secure_storage.dart';
import '../models/chat_message_model.dart';
import '../services/ai_service.dart';
import '../services/voice_service.dart';
import '../services/voice_state_machine.dart';

class VoiceViewModel extends ChangeNotifier {
  static const _listenWindow = Duration(seconds: 12);

  VoiceViewModel({
    VoiceEngine? voice,
    AiService? aiService,
    SecureStorage? storage,
    AppWebSocketService Function(String url, String? token)? wsFactory,
  })  : _voice = voice ?? VoiceService(),
        _ai = aiService ?? AiService(),
        _storage = storage ?? SecureStorage.instance,
        _wsFactory = wsFactory ??
            ((url, token) => AppWebSocketService(url: url, token: token)) {
    // Single source of truth for the hands-free loop: the machine owns the mic gate and the
    // turn ids, so the app can never transcribe its own TTS output.
    _machine = VoiceStateMachine(
      engine: _voice,
      onStateChanged: _onTurnStateChanged,
      onResult: _onRecognizerResult,
      onSilence: _onSilenceDetected,
      onError: _onRecognizerError,
    );
  }

  late final VoiceStateMachine _machine;

  /// Turn id of the request currently being processed, used to bind the spoken answer and its
  /// playback-completion callback to the same conversational turn.
  String? _currentTurnId;

  final VoiceEngine _voice;
  final AiService _ai;
  final SecureStorage _storage;
  final AppWebSocketService Function(String url, String? token) _wsFactory;
  AppWebSocketService? _ws;
  String? sessionId;
  bool isHelpMode = false;

  VoiceState state = VoiceState.idle;
  String liveTranscript = '';
  final List<ChatMessageModel> transcript = [];

  /// Latest session snapshot pushed by the scheduler (dishes, stoves, progress) - the cooking
  /// screen renders the recipe-steps panel from it.
  Map<String, dynamic>? lastSnapshot;

  /// True once the backend reports every dish finished (session status COMPLETED). The final
  /// "Happy meal!" line is still spoken, then the microphone and the heartbeat stop for good -
  /// the meal is over, nothing is left to schedule or listen for.
  bool mealComplete = false;

  /// When true the user is being asked "are you ready to start cooking?" and their answer is
  /// handled locally instead of being sent to the backend (the dish isn't added yet).
  bool readyCheckActive = false;
  Future<void> Function()? onUserReady;

  /// Ingredient screen supplies the exact current checklist candidates for command classification.
  Future<List<String>> Function()? onAvailableIngredients;
  Future<void> Function()? onHelpRequested;

  /// The Ingredient screen registers this so the assistant can read out whatever is still
  /// pending when the backend asks with a `remaining_items_request`.
  Future<List<String>> Function()? onRemainingItemsRequest;
  void Function(List<String> names)? onIngredientsRemoved;

  Timer? _listenWindowTimer;
  Timer? _heartbeatTimer;
  Timer? _sttRetryTimer;
  String _finalizedTranscript = '';
  String _partialTranscript = '';

  /// Highest server sequence number already handled on the current socket. The backend stamps
  /// every frame with a per-session `seq`, so a re-pushed snapshot or a frame delivered twice
  /// (two sockets registered for one session) is dropped instead of spoken again.
  int _lastSeq = 0;

  /// Bumped whenever the socket is replaced (init/detach/dispose) so a late frame from an
  /// already-discarded connection cannot be handled twice.
  int _wsEpoch = 0;
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  StreamSubscription<bool>? _wsConnSub;

  /// Exact text of the last thing we said, and when - used to swallow duplicates that arrive
  /// within a few seconds (double pushes, a replayed snapshot, a second socket).
  String? _lastSpokenText;
  DateTime? _lastSpokenAt;

  /// Spoken messages waiting their turn. Only one message is shown and one voice plays at a
  /// time; the next instruction starts as soon as the previous playback finishes, so two
  /// snapshots can never talk over each other.
  final List<_SpeechRequest> _speechQueue = [];
  bool _isSpeaking = false;

  /// Bumped whenever the screen re-initialises or detaches so a late playback completion from
  /// the previous screen cannot resume the microphone on this one.
  int _speechEpoch = 0;

  /// True while WE asked the recogniser to stop (end of a listen window, sending a command).
  /// The platform then reports `notListening`, which must not be mistaken for a timeout that
  /// needs an immediate restart - that flapping was `listening -> notListening -> listening`.

  /// Consecutive recogniser failures; drives the backoff so a permanent timeout cannot
  /// spin-restart forever. Reset as soon as real speech is recognised.
  int _sttErrorCount = 0;
  static const _sttBackoff = [500, 1000, 2000, 4000];

  /// False while the microphone is intentionally paused (e.g. the screen was left, or we're
  /// handing off to another screen). Prevents a finishing TTS playback from auto-resuming the mic.
  bool _active = false;
  bool _hasBackendSession = false;

  /// Live connection flag for the screen: while it is false the UI says so instead of
  /// looking like the assistant simply ignored the user (the socket retries silently).
  bool wsConnected = false;

  /// True once a socket has come up, so only a RE-connect asks the server what it missed
  /// (the first connect is driven by the screen itself).
  bool _wsConnectedOnce = false;

  /// Set when the microphone permission came back denied - there is then nothing to listen
  /// with, and the user has to be told instead of watching a dead mic button.
  bool micPermissionDenied = false;

  Future<void> init(String? sid, {bool helpMode = false}) async {
    print("VoiceViewModel: Initializing (HelpMode: $helpMode, Session: $sid)");
    // Tear down any previous socket/timers first so repeated init() calls (ingredient page ->
    // cooking page, helper assistant and back) never leave a second listener running.
    _wsSub?.cancel();
    _wsSub = null;
    _wsConnSub?.cancel();
    _wsConnSub = null;
    _wsEpoch++;
    _ws?.dispose();
    _ws = null;
    _listenWindowTimer?.cancel();
    _heartbeatTimer?.cancel();
    _sttRetryTimer?.cancel();
    _sttRetryTimer = null;
    _machine.dispose();
    _currentTurnId = null;
    _sttErrorCount = 0;

    isHelpMode = helpMode;
    _hasBackendSession = sid != null;
    sessionId = sid ?? const Uuid().v4();
    liveTranscript = '';
    _finalizedTranscript = '';
    _partialTranscript = '';
    state = VoiceState.idle;
    _active = true;
    readyCheckActive = false;
    onUserReady = null;
    // A cooking conversation is temporal: each screen starts with a clean transcript, never
    // carrying over helper questions or ingredient checklist chatter from another screen.
    transcript.clear();
    _speechQueue.clear();
    _isSpeaking = false;
    _speechEpoch++;
    // onRemainingItemsRequest is intentionally NOT cleared here: the Ingredient screen
    // registers it while it sits underneath this one in the nav stack.
    lastSnapshot = null;
    mealComplete = false;
    _lastSeq = 0;
    _lastSpokenText = null;
    _lastSpokenAt = null;
    wsConnected = false;
    _wsConnectedOnce = false;
    micPermissionDenied = false;
    notifyListeners();

    // 1. Permissions & Setup
    final micGranted = await _voice.requestMicPermission();
    micPermissionDenied = micGranted != true;
    if (micPermissionDenied) notifyListeners();
    await _voice.initSpeech(
      onStatus: _handleSttStatus,
      onError: _onRecognizerError,
    );
    await _voice.initTts();

    // 2. WebSocket Connection (only for non-help mode if preferred, but safe to connect always)
    final token = await _storage.accessToken;
    _ws = _wsFactory(
        ApiConstants.wsVoiceAssistant(token ?? '', sessionId!), token);
    _ws!.connect();
    // connect() reports failures through the listener below; the first `true` it would emit
    // happens before the listener exists, so record the first connect here to keep a later
    // drop-and-return distinguishable from it.
    wsConnected = true;
    _wsConnectedOnce = true;
    final epoch = _wsEpoch;
    _wsSub = _ws!.messages.listen((msg) {
      if (epoch != _wsEpoch) return; // stale socket from an earlier init/detach
      _handleServerMessage(msg);
    });
    // On every (re)connect forget the last sequence number: the server's counter restarts
    // with a fresh connection, so keeping it would drop the new frames as duplicates.
    _wsConnSub = _ws!.connectionState.listen((connected) {
      if (epoch != _wsEpoch) return;
      final changed = wsConnected != connected;
      wsConnected = connected;
      if (connected) {
        final isReconnect = _wsConnectedOnce;
        _wsConnectedOnce = true;
        _lastSeq = 0;
        // A dropped socket means the kitchen kept cooking without us: ask for the current
        // state again (the answer is a replay frame, so it only speaks if it says anything new).
        if (isReconnect &&
            !isHelpMode &&
            _hasBackendSession &&
            !readyCheckActive) {
          requestStatus();
        }
      }
      if (changed) notifyListeners();
    });
    _startSessionHeartbeat();

    // 3. Auto-start listening
    await startListening();
  }

  void _handleSttStatus(String status) {
    debugPrint("STT Status changed: $status");
    _machine.handleStatus(status);
  }

  void _onRecognizerError(String code, bool permanent) {
    debugPrint("STT error: $code (permanent: $permanent)");
    if (!_active || mealComplete) return;
    if (_machine.state != VoiceTurnState.listening &&
        _machine.state != VoiceTurnState.error) {
      return;
    }
    if (_sttRetryTimer != null) return;

    // Keep the microphone closed while backing off; the retry reopens it through the machine.
    _machine.noteError();
    final step = (_sttErrorCount < _sttBackoff.length)
        ? _sttErrorCount
        : _sttBackoff.length - 1;
    _sttErrorCount++;
    _sttRetryTimer = Timer(Duration(milliseconds: _sttBackoff[step]), () async {
      _sttRetryTimer = null;
      if (!_active || mealComplete) return;
      await _machine.restartListening();
      _armListenWindow();
    });
  }

  /// The platform stopped the recogniser on silence. Restart it (keeping the pending transcript)
  /// - only the listening window decides when a turn actually starts.
  void _onSilenceDetected() {
    _machine.restartListening();
    _armListenWindow();
  }

  void _onRecognizerResult(String text, bool isFinal) {
    // The machine only forwards results while the mic is allowed to be heard, so TTS can never
    // be transcribed back into a command.
    _updateTranscript(text, isFinal);
    notifyListeners();
  }

  void _onTurnStateChanged(VoiceTurnState turnState) {
    switch (turnState) {
      case VoiceTurnState.idle:
      case VoiceTurnState.error:
        _cancelListenWindow();
        state = VoiceState.idle;
        break;
      case VoiceTurnState.listening:
        state = VoiceState.listening;
        _armListenWindow();
        break;
      case VoiceTurnState.processing:
        _cancelListenWindow();
        state = VoiceState.thinking;
        break;
      case VoiceTurnState.speaking:
        _cancelListenWindow();
        state = VoiceState.speaking;
        break;
    }
    notifyListeners();
  }

  void _armListenWindow() {
    _listenWindowTimer?.cancel();
    _listenWindowTimer = Timer(_listenWindow, _finishListenWindow);
  }

  void _cancelListenWindow() {
    _listenWindowTimer?.cancel();
    _listenWindowTimer = null;
  }

  Future<void> startListening() async {
    _active = true;
    // The meal is over: the backend stopped scheduling and we already said goodbye.
    if (mealComplete) return;
    await _machine.start();
    if (_machine.state == VoiceTurnState.listening) _armListenWindow();
  }

  void _updateTranscript(String text, bool isFinal) {
    final recognized = text.trim();
    if (recognized.isEmpty) return;
    // Real speech means the recogniser is healthy again - clear the error backoff.
    _sttErrorCount = 0;
    _sttRetryTimer?.cancel();
    _sttRetryTimer = null;

    final finalizedLower = _finalizedTranscript.toLowerCase();
    final recognizedLower = recognized.toLowerCase();
    if (isFinal) {
      var completed = recognized;
      if (_partialTranscript.isNotEmpty &&
          !recognizedLower.startsWith(_partialTranscript.toLowerCase()) &&
          (finalizedLower.isEmpty ||
              !recognizedLower.startsWith(finalizedLower))) {
        completed = '$_partialTranscript $recognized';
      }
      if (finalizedLower.isEmpty ||
          recognizedLower.startsWith(finalizedLower)) {
        _finalizedTranscript = completed;
      } else if (!completed.toLowerCase().startsWith(finalizedLower) &&
          completed.toLowerCase() != finalizedLower) {
        _finalizedTranscript = '$_finalizedTranscript $completed'.trim();
      } else {
        _finalizedTranscript = completed;
      }
      liveTranscript = _finalizedTranscript;
      _partialTranscript = '';
      return;
    }

    _partialTranscript = recognized;
    if (finalizedLower.isEmpty || recognizedLower.startsWith(finalizedLower)) {
      liveTranscript = recognized;
    } else if (recognizedLower == finalizedLower) {
      liveTranscript = _finalizedTranscript;
    } else {
      liveTranscript = '$_finalizedTranscript $recognized'.trim();
    }
  }

  Future<void> _finishListenWindow() async {
    _listenWindowTimer = null;
    if (!_active || _machine.state != VoiceTurnState.listening) return;

    final text = liveTranscript.trim();
    if (text.isNotEmpty) {
      _sendUserText(text);
      return;
    }

    // Nothing was said: just reopen the window.
    await _machine.restartListening();
    _armListenWindow();
  }

  Future<void> stopListening() async {
    _cancelListenWindow();
    _sttRetryTimer?.cancel();
    _sttRetryTimer = null;
    await _machine.pause();
    notifyListeners();
  }

  /// Stops the microphone but keeps the socket alive (used when opening the helper assistant so
  /// the same session can be resumed when the user comes back).
  Future<void> pause() async {
    _active = false;
    _speechEpoch++;
    _speechQueue.clear();
    _isSpeaking = false;
    await stopListening();
  }

  /// Stops listening AND closes the socket. Use when handing a session off to another screen
  /// (e.g. Ingredients -> Cooking) so two sockets don't both speak the same instruction.
  Future<void> detach() async {
    await pause();
    pauseSessionHeartbeat();
    _wsSub?.cancel();
    _wsSub = null;
    _wsConnSub?.cancel();
    _wsConnSub = null;
    _wsEpoch++;
    _ws?.dispose();
    _ws = null;
    sessionId = null;
  }

  /// Asks the backend to re-send the current session snapshot (which is then spoken).
  void requestStatus() {
    if (isHelpMode) return;
    _ws?.send({'type': 'status'});
  }

  void _sendUserText(String text) async {
    // Nothing is left to cook - ignore stray speech/typing after the final farewell.
    if (!isHelpMode && mealComplete) return;
    if (!isHelpMode && onHelpRequested != null && _isHelpRequest(text)) {
      _listenWindowTimer?.cancel();
      _listenWindowTimer = null;
      liveTranscript = '';
      _finalizedTranscript = '';
      _partialTranscript = '';
      await pause();
      await onHelpRequested?.call();
      return;
    }

    _cancelListenWindow();

    // Reset live text so it's not visible while thinking
    liveTranscript = '';
    _finalizedTranscript = '';
    _partialTranscript = '';

    // Silence became a turn: the machine mints its id and closes the microphone BEFORE the
    // request leaves, so nothing the speaker plays can be transcribed back in.
    final turnId = await _machine.beginProcessing();
    _currentTurnId = turnId;
    if (!_active) return;

    transcript.add(ChatMessageModel(text: text, sender: ChatSender.user));
    notifyListeners();

    // Ready-check: the dish hasn't been added to the session yet, so answer locally.
    if (readyCheckActive) {
      await _handleReadyCheck(text);
      return;
    }

    if (isHelpMode) {
      print("DEBUG: Sending Help Question -> '$text'");
      final res = await _ai.askHelp(text);
      if (res is Success<String>) {
        _handleServerMessage({'type': 'prompt', 'message': res.data});
      } else if (res is Failure<String>) {
        _handleServerMessage({'type': 'error', 'message': res.message});
      }
    } else {
      final fastPath = _fastPathCommand(text);
      if (fastPath != null) {
        // An unambiguous one-word instruction skips the classification round trip: the
        // backend applies exactly the same action to a command_result, so "next"/"repeat"/
        // "stop" must never wait on a network call (let alone Gemini) to take effect.
        print("DEBUG: Keyword fast-path -> $fastPath");
        _ws?.send({
          'type': 'command_result',
          'sessionId': sessionId,
          'text': text,
          'result': VoiceCommandResult(command: fastPath).toJson(),
          'turnId': _currentTurnId,
        });
        return;
      }
      print("DEBUG: Sending Command Transcript -> '$text'");
      final availableIngredients =
          await onAvailableIngredients?.call() ?? const <String>[];
      final result = await _ai.classifyCommand(
        text,
        availableIngredientNames: availableIngredients,
      );
      switch (result) {
        case Success(data: final command):
          _ws?.send({
            'type': 'command_result',
            'sessionId': sessionId,
            'text': text,
            'result': command.toJson(),
            'turnId': _currentTurnId,
          });
        case Failure():
          // The socket path applies the same deterministic fallback classifier if REST is unavailable.
          _ws?.send({
            'type': 'user_text',
            'sessionId': sessionId,
            'text': text,
            'transcript': text,
            'availableIngredientNames': availableIngredients,
            'turnId': _currentTurnId,
          });
      }
    }
  }

  /// Utterances that need no understanding of context at all: the backend maps these exact
  /// phrases to the same commands, so sending them straight as a command_result removes a
  /// classification round trip from the most latency-sensitive controls. Anything longer or
  /// not listed (ingredient names, stove numbers, questions) still goes to the classifier.
  static const _fastPathCommands = <String, String>{
    'next': 'NEXT',
    'done': 'NEXT',
    "i'm done": 'NEXT',
    'i am done': 'NEXT',
    'finished': 'NEXT',
    'wait': 'WAIT',
    'not yet': 'WAIT',
    'hold on': 'WAIT',
    'repeat': 'REPEAT',
    'say that again': 'REPEAT',
    'what did you say': 'REPEAT',
    'stop': 'STOP',
    'cancel': 'STOP',
    'pause everything': 'STOP',
    'help': 'HELP',
  };

  static bool _isHelpRequest(String raw) {
    final normalized = raw
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[.!?,]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
    return normalized == 'help' ||
        normalized.startsWith('help me') ||
        normalized.startsWith('open help') ||
        normalized.startsWith('open the helper') ||
        normalized.startsWith('i need help');
  }

  static String? _fastPathCommand(String raw) {
    var t = raw.toLowerCase().trim();
    while (t.isNotEmpty && '!.?'.contains(t[t.length - 1])) {
      t = t.substring(0, t.length - 1).trimRight();
    }
    if (t.length > 24) return null;
    return _fastPathCommands[t];
  }

  void _startSessionHeartbeat() {
    _heartbeatTimer?.cancel();
    if (!_hasBackendSession || sessionId == null) return;
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => _sendHeartbeat(),
    );
  }

  void _sendHeartbeat() {
    if (_hasBackendSession && sessionId != null) {
      _ws?.send({'type': 'heartbeat', 'sessionId': sessionId});
    }
  }

  void pauseSessionHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void resumeSessionHeartbeat() {
    _sendHeartbeat();
    _startSessionHeartbeat();
  }

  /// Sends text typed into the chat input field through the exact same pipeline as speech.
  void sendTypedText(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    _sendUserText(t);
  }

  /// Asks "are you ready to start cooking?" before any step is dispatched.
  Future<void> beginReadyCheck(
      {required Future<void> Function() onReady, bool announce = true}) async {
    readyCheckActive = true;
    onUserReady = onReady;
    if (announce) {
      _listenWindowTimer?.cancel();
      _listenWindowTimer = null;
      // Mute rather than pause: the machine stays active so the announcement is still spoken and
      // the microphone reopens once playback completes.
      await _machine.mute();
      _speak('All ingredients are gathered. Are you ready to start cooking?');
    }
  }

  Future<void> _handleReadyCheck(String text) async {
    final t = text.toLowerCase().trim();
    if (_looksLikeNo(t)) {
      _speak(
          'No problem - take your time. Say "ready" when you want to start cooking.');
      return;
    }
    if (_looksLikeYes(t)) {
      readyCheckActive = false;
      final cb = onUserReady;
      onUserReady = null;
      notifyListeners();
      if (cb != null) await cb();
      return;
    }
    _speak('Are you ready to start cooking? Say yes or no.');
  }

  bool _looksLikeNo(String t) {
    return t == 'no' ||
        t == 'nope' ||
        t.startsWith('no ') ||
        t.startsWith('nope') ||
        t.contains('not ready') ||
        t.contains('not yet') ||
        t.contains('not now') ||
        t.startsWith('wait') ||
        t.contains('hold on') ||
        t.contains('give me') ||
        t.contains('later') ||
        t.contains('a minute') ||
        t.contains('few minutes');
  }

  bool _looksLikeYes(String t) {
    return t == 'yes' ||
        t == 'yeah' ||
        t == 'yep' ||
        t == 'yup' ||
        t == 'sure' ||
        t == 'ok' ||
        t == 'okay' ||
        t == 'ready' ||
        t == 'start' ||
        t == 'go' ||
        t == 'begin' ||
        t.startsWith('yes') ||
        t.startsWith('sure') ||
        t.startsWith('ready') ||
        t.startsWith("let's") ||
        t.startsWith('lets') ||
        t.startsWith('go ahead') ||
        t.startsWith('i am ready') ||
        t.startsWith("i'm ready") ||
        t.contains('ready to cook') ||
        t.contains('start cooking');
  }

  /// Public speak helper (used e.g. to announce a failed start-cooking attempt).
  void speakText(String text, {String? audioBase64}) =>
      _speak(text, audioBase64: audioBase64);

  void _handleServerMessage(Map<String, dynamic> msg) {
    print("WS RECEIVED FULL JSON: $msg");
    // Duplicate delivery of a frame we already handled - the same instruction twice is never
    // a new instruction, so drop it before it can add a chat bubble and speak again.
    final seq = msg['seq'];
    if (seq is num) {
      final s = seq.toInt();
      if (s <= _lastSeq) {
        debugPrint("WS: dropped duplicate seq=$s (last handled $_lastSeq)");
        return;
      }
      _lastSeq = s;
    }
    if (!_active) return;
    final type = msg['type']?.toString();
    final data = msg['data'] as Map<String, dynamic>?;

    if (type == 'connected') {
      _sendHeartbeat();
      return;
    }

    // 0. Session snapshots (pushed by the scheduler, or requested with {"type":"status"} when a
    //    cooking screen opens). The spoken text lives under data.message.
    if (type == 'session_snapshot') {
      if (data != null) lastSnapshot = data;
      _markMealCompleteIfDone(data);
      final text =
          data?['message']?.toString() ?? msg['message']?.toString() ?? '';
      final audioBase64 = data?['messageAudioBase64']?.toString() ??
          msg['messageAudioBase64']?.toString() ??
          data?['audioBase64']?.toString();
      if (text.isNotEmpty) {
        // A replay only exists so the screen isn't stale: if it repeats the instruction the
        // user just heard, update the state and stay silent.
        final repeatsLast = transcript.isNotEmpty &&
            transcript.last.sender == ChatSender.assistant &&
            transcript.last.text == text;
        if (msg['replay'] == true && repeatsLast) {
          debugPrint("WS: replayed snapshot already said - staying silent");
          return;
        }
        _speak(text, audioBase64: audioBase64);
      }
      return;
    }

    // The backend classified the utterance as "what's left on the list?" - ask the Ingredient
    // screen for its pending items and read them out.
    if (type == 'remaining_items_request') {
      _speakRemainingItems();
      return;
    }

    if (type == 'remove_ingredient') {
      final rawNames = data?['ingredientNames'] ?? msg['ingredientNames'];
      final names = rawNames is List
          ? rawNames
              .map((name) => name.toString().trim())
              .where((name) => name.isNotEmpty)
              .toList()
          : <String>[];
      if (names.isEmpty) {
        final name = data?['ingredientName']?.toString() ??
            msg['ingredientName']?.toString();
        if (name != null && name.trim().isNotEmpty) names.add(name.trim());
      }
      if (names.isNotEmpty) onIngredientsRemoved?.call(names);
      return;
    }

    // 1. Handle command classification (REMOVE, HELP, etc)
    final command = msg['command']?.toString() ?? data?['command']?.toString();
    if (command != null) {
      print("DEBUG: Identified Command Type -> $command");
      if (command != 'UNKNOWN') {
        if (command == 'REMOVE') {
          final ing = msg['ingredientName']?.toString() ??
              data?['ingredientName']?.toString();
          final serverMessage =
              msg['message']?.toString() ?? data?['message']?.toString();
          _speak(serverMessage ?? "Okay, removing $ing from your list.");
          return;
        }
        if (command == 'HELP') {
          final help = msg['helpResponse']?.toString() ??
              data?['helpResponse']?.toString();
          if (help != null) _speak(help);
          return;
        }
      }
    }

    // 2. Handle prompt messages (Common in HELP mode or direct prompts)
    if (type != 'error' && (type == 'prompt' || msg.containsKey('message'))) {
      final text =
          msg['message']?.toString() ?? data?['message']?.toString() ?? '';
      final audioBase64 = msg['messageAudioBase64']?.toString() ??
          data?['messageAudioBase64']?.toString() ??
          msg['audioBase64']?.toString() ??
          data?['audioBase64']?.toString();
      if (text.isNotEmpty) {
        _speak(text, audioBase64: audioBase64);
      }
      return;
    }

    // 3. Handle standard text/session reply
    final reply = msg['text']?.toString() ?? data?['text']?.toString();
    if (reply != null && reply.isNotEmpty && type != 'error') {
      if (transcript.isNotEmpty &&
          transcript.last.text == reply &&
          transcript.last.sender == ChatSender.assistant) return;

      if (reply.toLowerCase().contains('unknown action') && !isHelpMode) {
        _speak(
            "I'm sorry, I didn't understand that command. Could you please say it differently?");
      } else {
        _speak(reply);
      }
      return;
    }

    if (type == 'error') {
      final errMsg = reply ??
          msg['message']?.toString() ??
          "Sorry, I encountered an error.";
      if (!errMsg.toLowerCase().contains('unknown action')) {
        _speak(errMsg);
      }
    }
  }

  /// Remembers that the meal is finished (session COMPLETED or every dish COMPLETED). The final
  /// message is still spoken, but no new listening window or heartbeat is started afterwards.
  void _markMealCompleteIfDone(Map<String, dynamic>? data) {
    if (data == null || mealComplete || isHelpMode) return;
    final status = data['sessionStatus']?.toString();
    final dishes = data['dishes'];
    final allDishesDone = dishes is List &&
        dishes.isNotEmpty &&
        dishes.every((dish) =>
            dish is Map && dish['status']?.toString() == 'COMPLETED');
    if (status != 'COMPLETED' && !allDishesDone) return;
    mealComplete = true;
    _listenWindowTimer?.cancel();
    _listenWindowTimer = null;
    pauseSessionHeartbeat();
    notifyListeners();
  }

  Future<void> _speakRemainingItems() async {
    List<String> items = const [];
    final cb = onRemainingItemsRequest;
    if (cb != null) {
      try {
        items = await cb();
      } catch (_) {
        items = const [];
      }
    }
    final msg = items.isEmpty
        ? "You've got everything you need - nothing is left on the list."
        : 'You still need: ${items.join(', ')}.';
    _speak(msg);
  }

  void _speak(String text, {String? audioBase64}) {
    if (!_active) return;

    // Say the identical thing twice within a few seconds only when it is genuinely a new
    // instruction; otherwise it is a duplicate frame (double push, second socket, replay) and
    // the player from the first one is still running.
    final now = DateTime.now();
    if (text == _lastSpokenText &&
        _lastSpokenAt != null &&
        now.difference(_lastSpokenAt!) < const Duration(seconds: 8)) {
      print("Assistant Speaking: suppressed duplicate");
      return;
    }
    _lastSpokenText = text;
    _lastSpokenAt = now;

    _speechQueue.add(_SpeechRequest(text, audioBase64, _currentTurnId));
    _drainSpeechQueue();
  }

  /// Plays queued messages strictly one after another: the chat bubble and the voice for a
  /// message appear only once the previous message has finished speaking.
  ///
  /// Every playback is bound to a turn id. The microphone stays closed for the whole
  /// [VoiceTurnState.speaking] phase and is reopened only when the completion callback reports
  /// the turn that is still current - stale or duplicated callbacks are ignored.
  Future<void> _drainSpeechQueue() async {
    if (_isSpeaking || _speechQueue.isEmpty || !_active) return;

    _isSpeaking = true;
    final request = _speechQueue.removeAt(0);
    final epoch = _speechEpoch;
    // Responses to a user turn reuse its id; unsolicited pushes get one at speak time.
    final turnId = request.turnId ?? _currentTurnId;

    // Close the microphone BEFORE the first sample is played (echo gate).
    await _machine.speak(turnId);
    if (epoch != _speechEpoch) {
      _isSpeaking = false;
      return;
    }
    if (!_active) {
      _isSpeaking = false;
      return;
    }

    print("Assistant Speaking: ${request.text}");
    transcript.add(
        ChatMessageModel(text: request.text, sender: ChatSender.assistant));
    notifyListeners();

    Future<void> playback;
    if (request.audioBase64 != null && request.audioBase64!.isNotEmpty) {
      playback =
          _voice.synthesizeAndPlay(request.text, audioBase64: request.audioBase64);
    } else {
      playback = _voice.synthesizeAndPlay(request.text);
    }

    playback.catchError((Object error) {
      debugPrint('TTS playback failed: $error');
    }).whenComplete(() {
      if (epoch != _speechEpoch) return;
      _isSpeaking = false;
      if (!_active) return;
      if (_speechQueue.isNotEmpty) {
        _drainSpeechQueue();
        return;
      }
      print("Assistant Finished Speaking.");
      if (mealComplete) {
        // Last instruction of the meal played: keep the microphone and the voice pipeline off.
        print("Meal complete - stopping the voice assistant.");
        _machine.finishSpeaking(turnId);
        stopListening();
        return;
      }
      // Back to LISTENING only for the turn this playback belonged to.
      _machine.finishSpeaking(turnId);
    });
  }

  @override
  void dispose() {
    _speechEpoch++;
    _speechQueue.clear();
    _isSpeaking = false;
    _machine.dispose();
    _voice.dispose();
    _wsSub?.cancel();
    _wsSub = null;
    _wsConnSub?.cancel();
    _wsConnSub = null;
    _wsEpoch++;
    _ws?.dispose();
    _listenWindowTimer?.cancel();
    _heartbeatTimer?.cancel();
    _sttRetryTimer?.cancel();
    super.dispose();
  }
}

/// One queued spoken message: text plus the optional pre-rendered audio from the backend and
/// the conversational turn it answers (null for unsolicited pushes).
class _SpeechRequest {
  const _SpeechRequest(this.text, this.audioBase64, [this.turnId]);

  final String text;
  final String? audioBase64;
  final String? turnId;
}

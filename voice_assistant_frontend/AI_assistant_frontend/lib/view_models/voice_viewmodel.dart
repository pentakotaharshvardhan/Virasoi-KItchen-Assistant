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
            ((url, token) => AppWebSocketService(url: url, token: token));

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

  /// When true the user is being asked "are you ready to start cooking?" and their answer is
  /// handled locally instead of being sent to the backend (the dish isn't added yet).
  bool readyCheckActive = false;
  Future<void> Function()? onUserReady;

  /// Ingredient screen supplies the exact current checklist candidates for command classification.
  Future<List<String>> Function()? onAvailableIngredients;

  /// The Ingredient screen registers this so the assistant can read out whatever is still
  /// pending when the backend asks with a `remaining_items_request`.
  Future<List<String>> Function()? onRemainingItemsRequest;
  void Function(List<String> names)? onIngredientsRemoved;

  Timer? _listenWindowTimer;
  Timer? _heartbeatTimer;
  Timer? _sttRetryTimer;
  String _finalizedTranscript = '';
  String _partialTranscript = '';
  bool _isRestartingListener = false;
  bool _isClosingListenWindow = false;

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

  /// True while WE asked the recogniser to stop (end of a listen window, sending a command).
  /// The platform then reports `notListening`, which must not be mistaken for a timeout that
  /// needs an immediate restart - that flapping was `listening -> notListening -> listening`.
  bool _expectStop = false;

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
    _isClosingListenWindow = false;
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
    // onRemainingItemsRequest is intentionally NOT cleared here: the Ingredient screen
    // registers it while it sits underneath this one in the nav stack.
    lastSnapshot = null;
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
      onError: _handleSttError,
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
        if (isReconnect && !isHelpMode && _hasBackendSession && !readyCheckActive) {
          requestStatus();
        }
      }
      if (changed) notifyListeners();
    });
    _startSessionHeartbeat();

    // 3. Auto-start listening
    startListening();
  }

  void _handleSttStatus(String status) {
    debugPrint("STT Status changed: $status");
    // A stop we asked for ourselves - never treat it as a reason to restart.
    if (_expectStop) return;
    if ((status == 'done' || status == 'notListening') &&
        state == VoiceState.listening &&
        _active &&
        !_isClosingListenWindow) {
      _restartListener(preserveTranscript: true);
    }
  }

  /// Recogniser failures arrive as e.g. `error_speech_timeout, permanent: true`. Restarting
  /// straight away just re-enters the same failure, so back off instead - and only while the
  /// mic is actually supposed to be on.
  void _handleSttError(String code, bool permanent) {
    debugPrint("STT error: $code (permanent: $permanent)");
    if (!_active ||
        _expectStop ||
        _isClosingListenWindow ||
        state != VoiceState.listening) {
      return;
    }
    if (_isRestartingListener || _sttRetryTimer != null) return;

    final step = (_sttErrorCount < _sttBackoff.length)
        ? _sttErrorCount
        : _sttBackoff.length - 1;
    _sttErrorCount++;
    _sttRetryTimer = Timer(Duration(milliseconds: _sttBackoff[step]), () {
      _sttRetryTimer = null;
      if (!_active || state != VoiceState.listening) return;
      _restartListener(preserveTranscript: true);
    });
  }

  Future<void> _restartListener({required bool preserveTranscript}) async {
    if (_isRestartingListener) return;
    _isRestartingListener = true;
    try {
      await _startListeningInternal(preserveTranscript: preserveTranscript);
    } finally {
      _isRestartingListener = false;
    }
  }

  Future<void> startListening() async {
    _active = true;
    if (state == VoiceState.listening ||
        state == VoiceState.speaking ||
        state == VoiceState.thinking) return;

    _listenWindowTimer?.cancel();
    _listenWindowTimer = Timer(_listenWindow, _finishListenWindow);
    await _startListeningInternal();
  }

  Future<void> _startListeningInternal(
      {bool preserveTranscript = false}) async {
    print("Voice: Listening starting...");
    state = VoiceState.listening;
    // From here on any `notListening` is either a timeout or an error, never our own stop.
    _expectStop = false;
    if (!preserveTranscript) {
      liveTranscript = '';
      _finalizedTranscript = '';
      _partialTranscript = '';
    }
    notifyListeners();

    await _voice.startListening(
      onResult: (text, isFinal) {
        if (state != VoiceState.listening) return;

        _updateTranscript(text, isFinal);
        notifyListeners();
      },
    );
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
    if (state != VoiceState.listening || !_active) return;

    _isClosingListenWindow = true;
    _expectStop = true;
    try {
      await _voice.stopListening();
    } finally {
      _isClosingListenWindow = false;
    }

    if (state != VoiceState.listening || !_active) return;
    final text = liveTranscript.trim();
    if (text.isNotEmpty) {
      _sendUserText(text);
      return;
    }

    state = VoiceState.idle;
    notifyListeners();
    startListening();
  }

  Future<void> stopListening() async {
    _listenWindowTimer?.cancel();
    _listenWindowTimer = null;
    _sttRetryTimer?.cancel();
    _sttRetryTimer = null;
    _isClosingListenWindow = true;
    _expectStop = true;
    try {
      await _voice.stopListening();
    } finally {
      _isClosingListenWindow = false;
    }
    if (state == VoiceState.listening) state = VoiceState.idle;
    notifyListeners();
  }

  /// Stops the microphone but keeps the socket alive (used when opening the helper assistant so
  /// the same session can be resumed when the user comes back).
  Future<void> pause() async {
    _active = false;
    await stopListening();
    if (state != VoiceState.idle) {
      state = VoiceState.idle;
      notifyListeners();
    }
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
    _listenWindowTimer?.cancel();
    _listenWindowTimer = null;

    // Reset live text so it's not visible while thinking
    liveTranscript = '';
    _finalizedTranscript = '';
    _partialTranscript = '';
    transcript.add(ChatMessageModel(text: text, sender: ChatSender.user));
    state = VoiceState.thinking;
    notifyListeners();

    _expectStop = true;
    _voice.stopListening();

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
          });
        case Failure():
          // The socket path applies the same deterministic fallback classifier if REST is unavailable.
          _ws?.send({
            'type': 'user_text',
            'sessionId': sessionId,
            'text': text,
            'transcript': text,
            'availableIngredientNames': availableIngredients,
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
      await stopListening();
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

    print("Assistant Speaking: $text");

    // UI Update
    transcript.add(ChatMessageModel(text: text, sender: ChatSender.assistant));
    state = VoiceState.speaking;
    notifyListeners();

    // Play sound (Priority to backend audio if available)
    Future<void> playback;
    if (audioBase64 != null && audioBase64.isNotEmpty) {
      playback = _voice.synthesizeAndPlay(text, audioBase64: audioBase64);
    } else {
      // Fallback to synthesizing text via backend
      playback = _voice.synthesizeAndPlay(text);
    }

    playback.then((_) {
      print("Assistant Finished Speaking.");
      if (!_active) return;
      state = VoiceState.idle;
      notifyListeners();
      startListening(); // Auto-restart listening
    });
  }

  @override
  void dispose() {
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

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

  Timer? _stabilityTimer;
  Timer? _absoluteTimeoutTimer;
  String _lastLiveText = '';

  /// False while the microphone is intentionally paused (e.g. the screen was left, or we're
  /// handing off to another screen). Prevents a finishing TTS playback from auto-resuming the mic.
  bool _active = false;

  Future<void> init(String? sid, {bool helpMode = false}) async {
    print("VoiceViewModel: Initializing (HelpMode: $helpMode, Session: $sid)");
    // Tear down any previous socket/timers first so repeated init() calls (ingredient page ->
    // cooking page, helper assistant and back) never leave a second listener running.
    _ws?.dispose();
    _ws = null;
    _stabilityTimer?.cancel();
    _absoluteTimeoutTimer?.cancel();

    isHelpMode = helpMode;
    sessionId = sid ?? const Uuid().v4();
    liveTranscript = '';
    _lastLiveText = '';
    state = VoiceState.idle;
    _active = true;
    notifyListeners();

    // 1. Permissions & Setup
    await _voice.requestMicPermission();
    await _voice.initSpeech(onStatus: _handleSttStatus);
    await _voice.initTts();

    // 2. WebSocket Connection (only for non-help mode if preferred, but safe to connect always)
    final token = await _storage.accessToken;
    _ws = _wsFactory(ApiConstants.wsVoiceAssistant(token ?? '', sessionId!), token);
    _ws!.connect();
    _ws!.messages.listen(_handleServerMessage);

    // 3. Auto-start listening
    startListening();
  }

  void _handleSttStatus(String status) {
    debugPrint("STT Status changed: $status");
    // If the system shuts off the mic but app state is still 'listening', restart it.
    if ((status == 'done' || status == 'notListening') && state == VoiceState.listening) {
      if (liveTranscript.trim().isEmpty) {
        _startListeningInternal();
      }
    }
  }

  Future<void> startListening() async {
    _active = true;
    if (state == VoiceState.listening || state == VoiceState.speaking || state == VoiceState.thinking) return;

    _startAbsoluteTimeout();
    await _startListeningInternal();
  }

  Future<void> _startListeningInternal() async {
    print("Voice: Listening starting...");
    state = VoiceState.listening;
    liveTranscript = '';
    _lastLiveText = '';
    notifyListeners();

    await _voice.startListening(
      onResult: (text, isFinal) {
        if (state != VoiceState.listening) return;

        liveTranscript = text;
        notifyListeners();

        if (text.trim().isNotEmpty) {
          // Restart safety timers
          _startAbsoluteTimeout();

          // 10s logic: only start timer if we actually have some text
          _stabilityTimer?.cancel();
          _stabilityTimer = Timer(const Duration(seconds: 10), () {
            if (liveTranscript.trim().isNotEmpty && liveTranscript == _lastLiveText) {
              print("Voice: 10s stability reached for '$liveTranscript'. Sending...");
              _sendUserText(liveTranscript.trim());
            }
          });
          _lastLiveText = text;
        } else {
          // If text is empty (silent), just keep listening
          _stabilityTimer?.cancel();
        }

        if (isFinal && text.trim().isNotEmpty) {
          _sendUserText(text.trim());
        }
      },
    );
  }

  void _startAbsoluteTimeout() {
    _absoluteTimeoutTimer?.cancel();
    _absoluteTimeoutTimer = Timer(const Duration(minutes: 10), () {
      if (state == VoiceState.listening) {
        stopListening();
        state = VoiceState.idle;
        notifyListeners();
      }
    });
  }

  Future<void> stopListening() async {
    _stabilityTimer?.cancel();
    _absoluteTimeoutTimer?.cancel();
    await _voice.stopListening();
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
    _stabilityTimer?.cancel();
    _lastLiveText = '';
    
    // Reset live text so it's not visible while thinking
    liveTranscript = '';
    transcript.add(ChatMessageModel(text: text, sender: ChatSender.user));
    state = VoiceState.thinking;
    notifyListeners();
    
    _voice.stopListening();
    
    if (isHelpMode) {
      print("DEBUG: Sending Help Question -> '$text'");
      final res = await _ai.askHelp(text);
      if (res is Success<String>) {
        _handleServerMessage({'type': 'prompt', 'message': res.data});
      } else if (res is Failure<String>) {
        _handleServerMessage({'type': 'error', 'message': res.message});
      }
    } else {
      print("DEBUG: Sending Command Transcript -> '$text'");
      _ws?.send({
        'type': 'user_text', 
        'sessionId': sessionId, 
        'text': text,
        'transcript': text,
      });
    }
  }

  void _handleServerMessage(Map<String, dynamic> msg) {
    print("WS RECEIVED FULL JSON: $msg");
    if (!_active) return;
    final type = msg['type']?.toString();
    final data = msg['data'] as Map<String, dynamic>?;

    if (type == 'connected') {
      return;
    }

    // 0. Session snapshots (pushed by the scheduler, or requested with {"type":"status"} when a
    //    cooking screen opens). The spoken text lives under data.message.
    if (type == 'session_snapshot') {
      final text = data?['message']?.toString() ?? msg['message']?.toString() ?? '';
      final audioBase64 = data?['messageAudioBase64']?.toString()
          ?? msg['messageAudioBase64']?.toString()
          ?? data?['audioBase64']?.toString();
      if (text.isNotEmpty) _speak(text, audioBase64: audioBase64);
      return;
    }

    // 1. Handle command classification (REMOVE, HELP, etc)
    final command = msg['command']?.toString() ?? data?['command']?.toString();
    if (command != null) {
      print("DEBUG: Identified Command Type -> $command");
      if (command != 'UNKNOWN') {
        if (command == 'REMOVE') {
          final ing = msg['ingredientName']?.toString() ?? data?['ingredientName']?.toString();
          final serverMessage = msg['message']?.toString() ?? data?['message']?.toString();
          _speak(serverMessage ?? "Okay, removing $ing from your list.");
          return;
        }
        if (command == 'HELP') {
          final help = msg['helpResponse']?.toString() ?? data?['helpResponse']?.toString();
          if (help != null) _speak(help);
          return;
        }
      }
    }

    // 2. Handle prompt messages (Common in HELP mode or direct prompts)
    if (type != 'error' && (type == 'prompt' || msg.containsKey('message'))) {
      final text = msg['message']?.toString() ?? data?['message']?.toString() ?? '';
      final audioBase64 = msg['messageAudioBase64']?.toString()
          ?? data?['messageAudioBase64']?.toString()
          ?? msg['audioBase64']?.toString()
          ?? data?['audioBase64']?.toString();
      if (text.isNotEmpty) {
        _speak(text, audioBase64: audioBase64);
      }
      return;
    }

    // 3. Handle standard text/session reply
    final reply = msg['text']?.toString() ?? data?['text']?.toString();
    if (reply != null && reply.isNotEmpty && type != 'error') {
      if (transcript.isNotEmpty && transcript.last.text == reply && transcript.last.sender == ChatSender.assistant) return;
      
      if (reply.toLowerCase().contains('unknown action') && !isHelpMode) {
        _speak("I'm sorry, I didn't understand that command. Could you please say it differently?");
      } else {
        _speak(reply);
      }
      return;
    }

    if (type == 'error') {
      final errMsg = reply ?? msg['message']?.toString() ?? "Sorry, I encountered an error.";
      if (!errMsg.toLowerCase().contains('unknown action')) {
        _speak(errMsg);
      }
    }
  }

  void _speak(String text, {String? audioBase64}) {
    if (!_active) return;
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
    _ws?.dispose();
    _stabilityTimer?.cancel();
    _absoluteTimeoutTimer?.cancel();
    super.dispose();
  }
}

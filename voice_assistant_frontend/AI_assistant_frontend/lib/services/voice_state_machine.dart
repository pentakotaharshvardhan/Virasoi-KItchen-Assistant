import 'dart:async';

import 'voice_service.dart';

/// Phases of one hands-free conversation. They are mutually exclusive: only [listening] ever
/// has the microphone open.
enum VoiceTurnState { idle, listening, processing, speaking, error }

/// Deterministic voice state machine.
///
/// The old loop toggled the microphone around TTS with ad-hoc flags, so a slow platform callback
/// could reopen the mic while the speaker was still talking and the app transcribed its own
/// voice. This class removes that race with two hard rules:
///
///  1. **The microphone is only open in [VoiceTurnState.listening].** Entering [processing] or
///     [speaking] closes it, and any recogniser result that still arrives is dropped.
///  2. **Every turn is tagged.** A turn id is minted when the user stops talking and travels with
///     the request and the playback. Playback completion may only reopen the microphone if the
///     id it reports is still the current one, so late or duplicated callbacks are harmless.
///
/// All transitions are serialized through one future chain, so overlapping async callbacks can
/// never interleave a close and an open.
class VoiceStateMachine {
  VoiceStateMachine({
    required VoiceEngine engine,
    required this.onStateChanged,
    this.onResult,
    this.onSilence,
    this.onError,
  }) : _engine = engine;

  final VoiceEngine _engine;

  /// Fired for every real transition (never twice for the same state).
  final void Function(VoiceTurnState state) onStateChanged;

  /// Forwarded recogniser results - only while the machine is allowed to be heard.
  final void Function(String text, bool isFinal)? onResult;

  /// The platform stopped the recogniser on its own (silence / end of speech). The caller
  /// decides whether that transcript becomes a turn or the window simply restarts.
  final void Function()? onSilence;

  /// Recogniser failures (`code`, `permanent`), forwarded so the caller can back off.
  final void Function(String code, bool permanent)? onError;

  VoiceTurnState _state = VoiceTurnState.idle;
  VoiceTurnState get state => _state;

  bool _active = false;
  bool _micOpen = false;
  String? _turnId;
  int _turnCounter = 0;

  /// Serializes every transition. Tasks run one at a time, and the first one starts immediately
  /// (no extra microtask hop), so a state change requested from a platform callback takes effect
  /// before the next callback can observe a stale phase.
  final List<Future<void> Function()> _pending = [];
  bool _running = false;

  /// True while the machine itself asked the recogniser to stop. Used so that a platform
  /// `notListening` confirmation is not mistaken for the end of a user turn.
  bool _expectStop = false;

  bool get isActive => _active;
  bool get isMicOpen => _micOpen;
  String? get turnId => _turnId;

  /// Starts (or resumes) the loop and opens the microphone.
  Future<void> start() => _serialize(() async {
        _active = true;
        _expectStop = false;
        await _setState(VoiceTurnState.listening);
        await _openMic();
      });

  /// Stops the loop and closes the microphone. The machine stays reusable via [start].
  Future<void> pause() => _serialize(() async {
        _active = false;
        _turnId = null;
        await _closeMic();
        await _setState(VoiceTurnState.idle);
      });

  /// Closes the microphone and returns to [VoiceTurnState.idle] but keeps the machine active, so
  /// announcements can still be spoken and the loop resumes on the next [finishSpeaking].
  Future<void> mute() => _serialize(() async {
        _turnId = null;
        await _closeMic();
        await _setState(VoiceTurnState.idle);
      });

  /// Restarts the listening window without starting a turn (silence, empty transcript, or a
  /// recogniser restart after an error).
  Future<void> restartListening() => _serialize(() async {
        if (!_active) return;
        _expectStop = false;
        await _setState(VoiceTurnState.listening);
        await _closeMic(); // fresh audio buffer, never a half-open one
        await _openMic();
      });

  /// Silence became a turn: mints its id and closes the microphone before the request is sent.
  /// The returned id must be handed back to [speak] and [finishSpeaking].
  Future<String> beginProcessing() => _serialize(() async {
        final id = _newTurnId();
        _turnId = id;
        _expectStop = true;
        await _setState(VoiceTurnState.processing);
        await _closeMic();
        return id;
      });

  /// Enters [VoiceTurnState.speaking] and guarantees the microphone is shut. A response that
  /// isn't tied to a user turn (e.g. an unsolicited scheduler snapshot) gets its own turn id.
  Future<void> speak([String? turnId]) => _serialize(() async {
        if (!_active) return;
        if (turnId == null || turnId != _turnId) {
          _turnId = turnId ?? _newTurnId();
        }
        _expectStop = true;
        await _setState(VoiceTurnState.speaking);
        await _closeMic();
      });

  /// Playback finished. Reopens the microphone only when the completion belongs to the current
  /// turn; a stale callback (from a turn that was already superseded) is ignored.
  Future<void> finishSpeaking([String? turnId]) => _serialize(() async {
        if (turnId != null && _turnId != null && turnId != _turnId) return;
        _turnId = null;
        if (!_active) {
          await _setState(VoiceTurnState.idle);
          return;
        }
        await _setState(VoiceTurnState.listening);
        await _openMic();
      });

  /// Explicit failure path (network or playback). Never left stuck: the loop goes back to
  /// listening unless it was paused in the meantime.
  Future<void> fail() => _serialize(() async {
        _turnId = null;
        await _setState(VoiceTurnState.error);
        if (!_active) return;
        await _setState(VoiceTurnState.listening);
        await _openMic();
      });

  /// Recogniser reported an error. Keep the mic closed and surface [VoiceTurnState.error]; the
  /// caller's backoff timer is responsible for calling [restartListening].
  Future<void> noteError() => _serialize(() async {
        _micOpen = false;
        await _setState(VoiceTurnState.error);
      });

  /// Platform status changes. A `done`/`notListening` while we are genuinely listening means the
  /// user stopped talking; anything else (including our own stop) is ignored.
  void handleStatus(String status) {
    if (!_active || !_micOpen || _expectStop) return;
    if (_state != VoiceTurnState.listening) return;
    if (status == 'done' || status == 'notListening') {
      // The recogniser already stopped; keep the flag in sync so we don't close it twice.
      _micOpen = false;
      onSilence?.call();
    }
  }

  /// Recogniser failure callback from the engine.
  void handleError(String code, bool permanent) {
    if (!_active) return;
    onError?.call(code, permanent);
  }

  void dispose() {
    _active = false;
    _turnId = null;
    _micOpen = false;
    _state = VoiceTurnState.idle;
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _handleResult(String text, bool isFinal) {
    // Hard echo gate: TTS never leaks back in as a user utterance. Results are still accepted
    // in the error state so a few late segments can reset the caller's backoff, but the mic is
    // physically closed there anyway.
    if (!_active) return;
    if (_state != VoiceTurnState.listening && _state != VoiceTurnState.error) return;
    onResult?.call(text, isFinal);
  }

  Future<void> _setState(VoiceTurnState next) async {
    if (_state == next) return;
    _state = next;
    onStateChanged(next);
  }

  Future<void> _openMic() async {
    if (!_active || _state != VoiceTurnState.listening || _micOpen) return;
    _micOpen = true;
    _expectStop = false;
    try {
      await _engine.startListening(onResult: _handleResult);
    } catch (_) {
      _micOpen = false;
    }
  }

  Future<void> _closeMic() async {
    _micOpen = false;
    try {
      await _engine.stopListening();
    } catch (_) {
      // The engine may already be down; state stays authoritative either way.
    }
  }

  String _newTurnId() =>
      'turn_${DateTime.now().microsecondsSinceEpoch}_${++_turnCounter}';

  Future<T> _serialize<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _pending.add(() async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _pump();
    return completer.future;
  }

  void _pump() {
    if (_running || _pending.isEmpty) return;
    _running = true;
    final task = _pending.removeAt(0);
    task().whenComplete(() {
      _running = false;
      _pump();
    });
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:audioplayers/audioplayers.dart';

enum VoiceState { idle, listening, thinking, speaking }

/// Contract used by [VoiceViewModel]. Having an interface lets tests swap in
/// a fake without touching the STT/TTS/audio plugins.
abstract class VoiceEngine {
  Future<bool> requestMicPermission();

  /// [onStatus] reports recognizer status changes (`listening`, `notListening`, `done`...).
  /// [onError] reports recognizer failures as `(code, permanent)` so the caller can back off
  /// instead of hot-restarting into the same error forever.
  Future<bool> initSpeech({
    void Function(String status)? onStatus,
    void Function(String code, bool permanent)? onError,
  });

  Future<void> initTts();
  Future<void> startListening({
    required void Function(String text, bool isFinal) onResult,
  });
  Future<void> stopListening();
  bool get isListening;
  Future<void> speakLocally(String text);
  Future<void> synthesizeAndPlay(String text, {String? audioBase64});

  /// Stops whatever is currently audible. Used when another screen is about to take over the
  /// speaker, so two utterances can never play at the same time.
  Future<void> stopSpeaking();
  void dispose();
}

class VoiceService implements VoiceEngine {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();
  Completer<void>? _playbackCompleter;
  bool _sttReady = false;

  /// A `permanent: true` recognition error means the platform session is dead - the next
  /// listen() would silently do nothing, so we re-initialise first.
  bool _needsReinit = false;

  void Function(String status)? _onStatus;
  void Function(String code, bool permanent)? _onError;

  @override
  Future<bool> requestMicPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  @override
  Future<bool> initSpeech({
    void Function(String status)? onStatus,
    void Function(String code, bool permanent)? onError,
  }) async {
    if (onStatus != null) _onStatus = onStatus;
    if (onError != null) _onError = onError;
    if (_sttReady && !_needsReinit) return true;
    return _initialize();
  }

  Future<bool> _initialize() async {
    _needsReinit = false;
    try {
      _sttReady = await _speech.initialize(
        onError: (e) {
          debugPrint("STT Error: $e");
          if (e.permanent) _needsReinit = true;
          _onError?.call(e.errorMsg, e.permanent);
        },
        onStatus: (s) {
          debugPrint("STT Status: $s");
          _onStatus?.call(s);
        },
      );
    } catch (e) {
      debugPrint("STT init failed: $e");
      _sttReady = false;
    }
    return _sttReady;
  }

  @override
  Future<void> initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
  }

  @override
  Future<void> startListening({
    required void Function(String text, bool isFinal) onResult,
  }) async {
    // Re-initialise after a permanent error - otherwise listen() is a no-op.
    if (!_sttReady || _needsReinit) {
      if (!await _initialize()) return;
    }
    if (!_sttReady) return;

    await _speech.listen(
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      listenOptions: stt.SpeechListenOptions(
        listenFor: const Duration(seconds: 12),
        pauseFor: const Duration(seconds: 12),
        partialResults: true,
        // NOTE: no `onDevice: true`. On-device recognisers are missing on emulators and many
        // budget devices, which produced instant `error_speech_timeout` loops. Let the platform
        // pick its best available recogniser.
      ),
    );
  }

  @override
  Future<void> stopListening() async => _speech.stop();

  @override
  bool get isListening => _speech.isListening;

  /// Speaks text using local TTS fallback
  @override
  Future<void> speakLocally(String text) async {
    final completer = Completer<void>();
    _playbackCompleter = completer;
    _tts.setCompletionHandler(() {
      if (!completer.isCompleted) completer.complete();
    });
    await _tts.speak(text);
    await completer.future;
    if (identical(_playbackCompleter, completer)) _playbackCompleter = null;
  }

  /// Stops on-device speech or the pre-rendered clip and resolves the pending playback future,
  /// so a caller awaiting [synthesizeAndPlay] is never left hanging when we cut it off.
  @override
  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {
      // The engine may not be initialised yet.
    }
    try {
      await _audioPlayer.stop();
    } catch (_) {
      // Nothing was playing.
    }
    final pending = _playbackCompleter;
    _playbackCompleter = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  /// Plays the audio the backend attached to the message, otherwise speaks on-device.
  /// Deliberately does NOT call the synthesis endpoint when no audio arrived: if the backend
  /// had been able to synthesise the text, the audio would already be attached - asking it
  /// again only adds another network round trip in front of every spoken instruction.
  @override
  Future<void> synthesizeAndPlay(String text, {String? audioBase64}) async {
    if (audioBase64 != null && audioBase64.isNotEmpty) {
      try {
        final bytes = base64Decode(audioBase64);
        await _audioPlayer.play(BytesSource(Uint8List.fromList(bytes)));
        await _audioPlayer.onPlayerComplete.first;
        return;
      } catch (e) {
        debugPrint("Audio Service Error: $e");
      }
    }

    try {
      await speakLocally(text);
    } catch (e) {
      debugPrint("Audio Service Error: $e");
    }
  }

  @override
  void dispose() {
    _speech.stop();
    final pending = _playbackCompleter;
    _playbackCompleter = null;
    if (pending != null && !pending.isCompleted) pending.complete();
    _tts.stop();
    _audioPlayer.dispose();
  }
}

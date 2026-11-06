import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:audioplayers/audioplayers.dart';
import '../core/constants/api_constants.dart';
import '../core/network/api_client.dart';
import '../core/utils/result.dart';

enum VoiceState { idle, listening, thinking, speaking }

/// Contract used by [VoiceViewModel]. Having an interface lets tests swap in
/// a fake without touching the STT/TTS/audio plugins.
abstract class VoiceEngine {
  Future<bool> requestMicPermission();
  Future<bool> initSpeech({void Function(String status)? onStatus});
  Future<void> initTts();
  Future<void> startListening({
    required void Function(String text, bool isFinal) onResult,
  });
  Future<void> stopListening();
  bool get isListening;
  Future<void> speakLocally(String text);
  Future<void> synthesizeAndPlay(String text, {String? audioBase64});
  void dispose();
}

class VoiceService implements VoiceEngine {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _sttReady = false;

  @override
  Future<bool> requestMicPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  @override
  Future<bool> initSpeech({void Function(String status)? onStatus}) async {
    if (_sttReady) return true;
    _sttReady = await _speech.initialize(
      onError: (e) => debugPrint("STT Error: $e"),
      onStatus: (s) {
        if (onStatus != null) onStatus(s);
        debugPrint("STT Status: $s");
      },
    );
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
    if (!_sttReady) await initSpeech();
    if (!_sttReady) return;

    await _speech.listen(
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      listenOptions: stt.SpeechListenOptions(
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
        onDevice: true,
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
    _tts.setCompletionHandler(() => completer.complete());
    await _tts.speak(text);
    return completer.future;
  }

  /// Calls backend synthesis or plays provided audio
  @override
  Future<void> synthesizeAndPlay(String text, {String? audioBase64}) async {
    try {
      if (audioBase64 != null && audioBase64.isNotEmpty) {
        final bytes = base64Decode(audioBase64);
        await _audioPlayer.play(BytesSource(Uint8List.fromList(bytes)));
        await _audioPlayer.onPlayerComplete.first;
        return;
      }

      // No base64 provided, call synthesis endpoint
      final res = await ApiClient.instance.post(ApiConstants.synthesize, body: {'text': text});
      if (res is Success) {
        final data = res.data;
        String? b64;
        if (data is Map) {
          b64 = data['audio']?.toString() ?? data['audioContent']?.toString() ?? data['messageAudioBase64']?.toString();
        } else if (data is String) {
          b64 = data;
        }

        if (b64 != null && b64.isNotEmpty) {
          final bytes = base64Decode(b64);
          await _audioPlayer.play(BytesSource(Uint8List.fromList(bytes)));
          await _audioPlayer.onPlayerComplete.first;
        } else {
          await speakLocally(text);
        }
      } else {
        await speakLocally(text);
      }
    } catch (e) {
      debugPrint("Audio Service Error: $e");
      await speakLocally(text);
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();
    _audioPlayer.dispose();
  }
}

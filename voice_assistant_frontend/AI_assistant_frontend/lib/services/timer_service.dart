import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';

/// Represents one running cooking timer/alarm tied to a recipe step.
class CookingTimer {
  final String id;
  final String label;
  final int totalSeconds;
  int remainingSeconds;
  bool isRunning;
  Timer? _ticker;

  CookingTimer({
    required this.id,
    required this.label,
    required this.totalSeconds,
    int? remaining,
    this.isRunning = false,
  }) : remainingSeconds = remaining ?? totalSeconds;

  double get progress => totalSeconds == 0 ? 0 : 1 - (remainingSeconds / totalSeconds);
}

/// In-memory alarm/timer manager for step timers. Notifies listeners every
/// tick so any screen (recipe detail, a mini overlay, etc.) can show live
/// countdowns, and plays a chime + haptic-style callback when a timer ends.
class TimerService extends ChangeNotifier {
  TimerService._();
  static final TimerService instance = TimerService._();

  final Map<String, CookingTimer> _timers = {};
  AudioPlayer? _player;

  /// Lets unit tests exercise the countdown without touching the audioplayers
  /// platform channel.
  @visibleForTesting
  bool muteAlarms = false;

  List<CookingTimer> get activeTimers => _timers.values.toList();

  CookingTimer startTimer({required String id, required String label, required int seconds}) {
    _timers[id]?._ticker?.cancel();
    final t = CookingTimer(id: id, label: label, totalSeconds: seconds, isRunning: true);
    _timers[id] = t;
    t._ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick(id));
    notifyListeners();
    return t;
  }

  void pauseTimer(String id) {
    _timers[id]?.isRunning = false;
    _timers[id]?._ticker?.cancel();
    notifyListeners();
  }

  void resumeTimer(String id) {
    final t = _timers[id];
    if (t == null) return;
    t.isRunning = true;
    t._ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick(id));
    notifyListeners();
  }

  void cancelTimer(String id) {
    _timers[id]?._ticker?.cancel();
    _timers.remove(id);
    notifyListeners();
  }

  /// Clears every timer without firing alarms. Test-only helper so the
  /// singleton starts each test from a clean slate.
  @visibleForTesting
  void resetForTest() {
    for (final timer in _timers.values) {
      timer._ticker?.cancel();
    }
    _timers.clear();
    notifyListeners();
  }

  void _tick(String id) {
    final t = _timers[id];
    if (t == null) return;
    if (t.remainingSeconds <= 0) {
      t._ticker?.cancel();
      t.isRunning = false;
      _playAlarm();
    } else {
      t.remainingSeconds -= 1;
    }
    notifyListeners();
  }

  Future<void> _playAlarm() async {
    if (muteAlarms) return;
    try {
      // Drop an mp3 named "timer_done.mp3" under assets/ and register it in
      // pubspec assets to enable sound; fails silently otherwise.
      _player ??= AudioPlayer();
      await _player!.play(AssetSource('audio/timer_done.mp3'));
    } catch (_) {
      // no-op: sound asset optional
    }
  }
}

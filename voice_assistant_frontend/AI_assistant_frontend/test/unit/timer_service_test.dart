import 'package:ai_assistant_frontend/services/timer_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    TimerService.instance
      ..muteAlarms = true
      ..resetForTest();
  });
  tearDown(() {
    TimerService.instance
      ..muteAlarms = false
      ..resetForTest();
  });

  test('startTimer registers a running timer with full duration', () {
    final service = TimerService.instance;

    final timer = service.startTimer(id: 't1', label: 'Boil', seconds: 60);

    expect(timer.totalSeconds, 60);
    expect(timer.remainingSeconds, 60);
    expect(timer.isRunning, isTrue);
    expect(service.activeTimers.single.id, 't1');
  });

  test('ticks down once per second', () {
    fakeAsync((async) {
      final service = TimerService.instance;
      final timer = service.startTimer(id: 't1', label: 'Boil', seconds: 10);

      async.elapse(const Duration(seconds: 3));

      expect(timer.remainingSeconds, 7);
      expect(timer.isRunning, isTrue);
    });
  });

  test('stops and fires the alarm when the countdown reaches zero', () {
    fakeAsync((async) {
      final service = TimerService.instance;
      final timer = service.startTimer(id: 't1', label: 'Boil', seconds: 2);

      async.elapse(const Duration(seconds: 4));
      async.flushMicrotasks();

      expect(timer.remainingSeconds, 0);
      expect(timer.isRunning, isFalse);
    });
  });

  test('pause freezes the countdown and resume continues it', () {
    fakeAsync((async) {
      final service = TimerService.instance;
      final timer = service.startTimer(id: 't1', label: 'Boil', seconds: 10);

      async.elapse(const Duration(seconds: 3));
      service.pauseTimer('t1');
      async.elapse(const Duration(seconds: 5));

      expect(timer.remainingSeconds, 7);
      expect(timer.isRunning, isFalse);

      service.resumeTimer('t1');
      async.elapse(const Duration(seconds: 2));

      expect(timer.remainingSeconds, 5);
      expect(timer.isRunning, isTrue);
    });
  });

  test('cancelTimer removes the timer from the active list', () {
    final service = TimerService.instance;
    service.startTimer(id: 't1', label: 'Boil', seconds: 10);
    service.startTimer(id: 't2', label: 'Fry', seconds: 20);

    service.cancelTimer('t1');

    expect(service.activeTimers.map((t) => t.id), ['t2']);
  });

  test('progress is computed from elapsed time', () {
    fakeAsync((async) {
      final service = TimerService.instance;
      final timer = service.startTimer(id: 't1', label: 'Boil', seconds: 10);

      expect(timer.progress, 0);
      async.elapse(const Duration(seconds: 5));
      expect(timer.progress, closeTo(0.5, 0.001));
    });
  });

  test('notifies listeners on start, tick, pause and cancel', () {
    fakeAsync((async) {
      final service = TimerService.instance;
      var notifications = 0;
      service.addListener(() => notifications++);

      service.startTimer(id: 't1', label: 'Boil', seconds: 5);
      async.elapse(const Duration(seconds: 2));
      service.pauseTimer('t1');
      service.cancelTimer('t1');

      expect(notifications, greaterThanOrEqualTo(4));
    });
  });

  test('a zero-duration timer is stopped on the first tick', () {
    fakeAsync((async) {
      final service = TimerService.instance;
      final timer = service.startTimer(id: 't0', label: 'Done', seconds: 0);

      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();

      expect(timer.isRunning, isFalse);
      expect(timer.progress, 0);
    });
  });
}

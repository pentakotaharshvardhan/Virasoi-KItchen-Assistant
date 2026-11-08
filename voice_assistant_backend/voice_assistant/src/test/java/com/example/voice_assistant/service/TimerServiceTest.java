package com.example.voice_assistant.service;

import org.junit.jupiter.api.Test;
import org.springframework.scheduling.TaskScheduler;

import java.time.Duration;
import java.time.Instant;
import java.util.UUID;
import java.util.concurrent.ScheduledFuture;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.doReturn;

class TimerServiceTest {

    @Test
    void doesNotScheduleDuplicateRemindersAndSessionCancellationStopsEveryJob() {
        TaskScheduler taskScheduler = mock(TaskScheduler.class);
        ScheduledFuture<?> stepTimer = mock(ScheduledFuture.class);
        ScheduledFuture<?> reminder = mock(ScheduledFuture.class);
        doReturn(stepTimer).when(taskScheduler).schedule(any(Runnable.class), any(Instant.class));
        doReturn(reminder).when(taskScheduler).scheduleAtFixedRate(
                any(Runnable.class), any(Instant.class), any(Duration.class));

        TimerService timerService = new TimerService(taskScheduler);
        UUID sessionId = UUID.randomUUID();
        UUID stepId = UUID.randomUUID();
        timerService.startTimer(sessionId, stepId, 120, () -> {});
        timerService.startUserReminder(sessionId, stepId, Duration.ofMinutes(6), () -> {});
        timerService.startUserReminder(sessionId, stepId, Duration.ofMinutes(6), () -> {});

        verify(taskScheduler, times(1)).scheduleAtFixedRate(
                any(Runnable.class), any(Instant.class), any(Duration.class));

        timerService.cancelTimersForSession(sessionId);

        verify(stepTimer).cancel(false);
        verify(reminder).cancel(false);
    }
}

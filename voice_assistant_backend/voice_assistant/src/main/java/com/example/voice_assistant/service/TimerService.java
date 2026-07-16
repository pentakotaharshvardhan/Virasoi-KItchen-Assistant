package com.example.voice_assistant.service;

import org.springframework.scheduling.TaskScheduler;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ScheduledFuture;

/**
 * Runs cooking-step timers (chopping/boiling/resting/etc) without blocking any request thread.
 * Deliberately provider-agnostic about *what* happens when a timer elapses: the caller supplies
 * a callback (kept decoupled from SchedulerService to avoid a circular bean dependency).
 */
@Service
public class TimerService {

    private final TaskScheduler taskScheduler;
    private final Map<UUID, ScheduledFuture<?>> activeTimers = new ConcurrentHashMap<>();

    public TimerService(TaskScheduler taskScheduler) {
        this.taskScheduler = taskScheduler;
    }

    public void startTimer(UUID stepId, int seconds, Runnable onElapsed) {
        cancelTimer(stepId);
        Instant runAt = Instant.now().plusSeconds(Math.max(seconds, 0));
        ScheduledFuture<?> future = taskScheduler.schedule(() -> {
            activeTimers.remove(stepId);
            onElapsed.run();
        }, runAt);
        activeTimers.put(stepId, future);
    }

    public void cancelTimer(UUID stepId) {
        ScheduledFuture<?> existing = activeTimers.remove(stepId);
        if (existing != null) {
            existing.cancel(false);
        }
    }

    public boolean isRunning(UUID stepId) {
        ScheduledFuture<?> future = activeTimers.get(stepId);
        return future != null && !future.isDone();
    }
}

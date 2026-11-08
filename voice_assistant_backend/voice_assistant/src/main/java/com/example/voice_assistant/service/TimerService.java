package com.example.voice_assistant.service;

import jakarta.annotation.PreDestroy;
import org.springframework.scheduling.TaskScheduler;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ScheduledFuture;

/**
 * Runs cooking timers and user-task reminders without blocking request threads.
 * The session/step association lets cancellation clean up every scheduled job for a session.
 */
@Service
public class TimerService {

    private final TaskScheduler taskScheduler;
    private final Map<TimerKey, ScheduledFuture<?>> activeTimers = new ConcurrentHashMap<>();
    private final Map<UUID, UserReminder> userReminders = new ConcurrentHashMap<>();

    public TimerService(TaskScheduler taskScheduler) {
        this.taskScheduler = taskScheduler;
    }

    public synchronized void startTimer(UUID sessionId, UUID stepId, int seconds, Runnable onElapsed) {
        cancelTimer(stepId);
        TimerKey key = new TimerKey(sessionId, stepId);
        Instant runAt = Instant.now().plusSeconds(Math.max(seconds, 0));
        ScheduledFuture<?> future = taskScheduler.schedule(() -> {
            activeTimers.remove(key);
            onElapsed.run();
        }, runAt);
        activeTimers.put(key, future);
    }

    public synchronized void startUserReminder(
            UUID sessionId, UUID stepId, Duration interval, Runnable onReminder) {
        UserReminder current = userReminders.get(sessionId);
        if (current != null && current.stepId().equals(stepId) && !current.future().isDone()) return;
        cancelUserReminder(sessionId);

        ScheduledFuture<?> future = taskScheduler.scheduleAtFixedRate(
                onReminder, Instant.now().plus(interval), interval);
        userReminders.put(sessionId, new UserReminder(stepId, future));
    }

    public void cancelTimer(UUID stepId) {
        for (Map.Entry<TimerKey, ScheduledFuture<?>> entry : new ArrayList<>(activeTimers.entrySet())) {
            if (entry.getKey().stepId().equals(stepId)
                    && activeTimers.remove(entry.getKey(), entry.getValue())) {
                entry.getValue().cancel(false);
            }
        }
    }

    public synchronized void cancelUserReminder(UUID sessionId) {
        UserReminder reminder = userReminders.remove(sessionId);
        if (reminder != null) reminder.future().cancel(false);
    }

    public synchronized void cancelUserReminder(UUID sessionId, UUID stepId) {
        UserReminder reminder = userReminders.get(sessionId);
        if (reminder != null && reminder.stepId().equals(stepId)) {
            cancelUserReminder(sessionId);
        }
    }

    public void cancelTimersForSession(UUID sessionId) {
        for (Map.Entry<TimerKey, ScheduledFuture<?>> entry : new ArrayList<>(activeTimers.entrySet())) {
            if (entry.getKey().sessionId().equals(sessionId)
                    && activeTimers.remove(entry.getKey(), entry.getValue())) {
                entry.getValue().cancel(false);
            }
        }
        cancelUserReminder(sessionId);
    }

    public boolean isRunning(UUID stepId) {
        return activeTimers.entrySet().stream()
                .anyMatch(entry -> entry.getKey().stepId().equals(stepId)
                        && !entry.getValue().isDone());
    }

    @PreDestroy
    public void cancelAll() {
        activeTimers.values().forEach(future -> future.cancel(false));
        activeTimers.clear();
        userReminders.values().forEach(reminder -> reminder.future().cancel(false));
        userReminders.clear();
    }

    private record TimerKey(UUID sessionId, UUID stepId) {}
    private record UserReminder(UUID stepId, ScheduledFuture<?> future) {}
}

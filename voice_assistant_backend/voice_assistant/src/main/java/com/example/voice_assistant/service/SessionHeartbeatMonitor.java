package com.example.voice_assistant.service;

import com.example.voice_assistant.entity.enums.SessionStatus;
import com.example.voice_assistant.repository.CookingSessionRepository;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.time.Instant;

/** Cancels abandoned sessions only after a grace period, so brief backgrounding/network loss is safe. */
@Component
public class SessionHeartbeatMonitor {

    private final CookingSessionRepository sessionRepository;
    private final SchedulerService schedulerService;
    private final Duration gracePeriod;

    public SessionHeartbeatMonitor(
            CookingSessionRepository sessionRepository,
            SchedulerService schedulerService,
            @Value("${kitchen.session-heartbeat-grace:PT5M}") Duration gracePeriod) {
        this.sessionRepository = sessionRepository;
        this.schedulerService = schedulerService;
        this.gracePeriod = gracePeriod;
    }

    @Scheduled(fixedDelayString = "${kitchen.session-heartbeat-sweep-ms:30000}")
    public void cancelAbandonedSessions() {
        Instant cutoff = Instant.now().minus(gracePeriod);
        for (var sessionId : sessionRepository.findStaleSessionIds(SessionStatus.ACTIVE, cutoff)) {
            schedulerService.cancelIfHeartbeatExpired(sessionId, cutoff);
        }
    }
}

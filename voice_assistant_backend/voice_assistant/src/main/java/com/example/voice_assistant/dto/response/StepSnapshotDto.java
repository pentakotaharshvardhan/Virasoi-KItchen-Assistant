package com.example.voice_assistant.dto.response;

import java.util.UUID;

/** One step of one dish, as shown in the cooking screen's per-dish step flow. */
public class StepSnapshotDto {
    public UUID stepId;
    public int stepNumber;
    public String instruction;
    public String status;
    public String stepType;
    public Integer assignedStoveIndex;
    public boolean requiresTimer;
    public Integer timerSeconds;
    public Long secondsRemaining;
}

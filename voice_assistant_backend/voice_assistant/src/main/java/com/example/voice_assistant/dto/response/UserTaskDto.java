package com.example.voice_assistant.dto.response;

import java.util.UUID;

/** The single task currently assigned to the human user (only one at a time - the user is a single resource). */
public class UserTaskDto {
    public UUID sessionDishId;
    public UUID stepId;
    public String dishName;
    public String instruction;
    public String stepType;
    public String status; // IN_PROGRESS | TIMER_COMPLETED_AWAITING_USER
    public Boolean requiresTimer;
    public Integer timerSeconds;
}

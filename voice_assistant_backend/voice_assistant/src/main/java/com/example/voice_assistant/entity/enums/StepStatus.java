package com.example.voice_assistant.entity.enums;

public enum StepStatus {
    PENDING,                       // not started, waiting for a turn/resource
    IN_PROGRESS,                   // actively being worked (user action or stove step without a timer)
    TIMER_RUNNING,                 // stove/passive step with an active timer
    TIMER_COMPLETED_AWAITING_USER, // timer finished, waiting for user to say "next" or "wait"
    COMPLETED
}

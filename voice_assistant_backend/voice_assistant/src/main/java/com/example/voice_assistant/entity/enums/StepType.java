package com.example.voice_assistant.entity.enums;

/**
 * Classifies what resource a cooking step needs, which drives the
 * scheduling engine (see SchedulerService):
 *
 *  STOVE          - needs a stove, but not the user's active attention
 *  USER_ACTION    - needs the user's hands, but no stove
 *  STOVE_AND_USER - needs both resources at the same time
 *  PASSIVE        - needs neither resource right now
 */
public enum StepType {
    STOVE,
    USER_ACTION,
    STOVE_AND_USER,
    PASSIVE;

    public boolean requiresStove() {
        return this == STOVE || this == STOVE_AND_USER;
    }

    public boolean requiresUser() {
        return this == USER_ACTION || this == STOVE_AND_USER;
    }
}

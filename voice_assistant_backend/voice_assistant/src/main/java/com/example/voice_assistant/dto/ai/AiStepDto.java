package com.example.voice_assistant.dto.ai;

public class AiStepDto {
    public int stepNumber;
    public String instruction;
    /** Expected values: "STOVE", "USER_ACTION", "PASSIVE" */
    public String stepType;
    public boolean requiresTimer;
    public Integer timerSeconds;
    public boolean scalesWithServes;

    public AiStepDto() {}
}

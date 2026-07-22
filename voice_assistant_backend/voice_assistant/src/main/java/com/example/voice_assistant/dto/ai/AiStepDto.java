package com.example.voice_assistant.dto.ai;


public class AiStepDto {
    public int stepNumber;
    public String instruction;
    /** Expected values: "STOVE", "USER_ACTION", "PASSIVE" */
    public String stepType;
    public boolean requiresTimer;
    public Integer timerSeconds;
    public boolean scalesWithServes;
    /** Exact name of one entry in this recipe's `ingredients[]`, if this step measures out a
     *  specific ingredient (e.g. "salt"). Null for steps with no single associated ingredient
     *  (e.g. "heat oil in the pan", "plate and serve"). */
    public String ingredientName; // ADD

    public AiStepDto() {}
}

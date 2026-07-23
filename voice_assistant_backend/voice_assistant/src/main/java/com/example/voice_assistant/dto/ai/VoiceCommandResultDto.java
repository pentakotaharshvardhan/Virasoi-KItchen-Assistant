package com.example.voice_assistant.dto.ai;

public class VoiceCommandResultDto {
    /** NEXT, WAIT, TIMER_YES, TIMER_NO, REPEAT, STOP, REMOVE, HELP, UNKNOWN */
    public String command;
    public Integer stoveIndex;
    public String dishName;
    public String ingredientName;
    public Integer timerSeconds;
    /** Only set when command == HELP: Gemini's direct answer to the user's app-usage question. */
    public String helpResponse;

    public VoiceCommandResultDto() {}
}

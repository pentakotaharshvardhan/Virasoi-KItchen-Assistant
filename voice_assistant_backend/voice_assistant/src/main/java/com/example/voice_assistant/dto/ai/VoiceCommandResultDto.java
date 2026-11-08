package com.example.voice_assistant.dto.ai;

import java.util.List;

public class VoiceCommandResultDto {
    /** NEXT, WAIT, TIMER_YES, TIMER_NO, REPEAT, STOP, REMOVE, FREE_USER, REMAINING_ITEMS, HELP, UNKNOWN */
    public String command;
    /** All explicitly named stove indices, in spoken order. */
    public List<Integer> stoveIndices;
    /** Backward-compatible first stove index. */
    public Integer stoveIndex;
    public String dishName;
    public String ingredientName;
    public List<String> ingredientNames;
    public Integer timerSeconds;
    /** Only set when command == HELP: Gemini's direct answer to the user's app-usage question. */
    public String helpResponse;

    public VoiceCommandResultDto() {}
}

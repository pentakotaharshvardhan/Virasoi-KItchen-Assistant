package com.example.voice_assistant.dto.ai;

import java.util.ArrayList;
import java.util.List;

/** Strict JSON shape returned when Gemini generates several standalone recipes in one call. */
public class AiRecipeBatchResponseDto {
    public List<AiRecipeResponseDto> recipes = new ArrayList<>();

    public AiRecipeBatchResponseDto() {}
}

package com.example.voice_assistant.dto.ai;

import java.util.ArrayList;
import java.util.List;

/** Strict JSON shape we instruct the AI to return, for both ancestor-recipe formatting and fresh recipe generation. */
public class AiRecipeResponseDto {
    public String dishName;
    public String description;
    public List<AiIngredientDto> ingredients = new ArrayList<>();
    public List<AiStepDto> steps = new ArrayList<>();

    public AiRecipeResponseDto() {}
}

package com.example.voice_assistant.dto.request;

import jakarta.validation.constraints.NotBlank;

public class GenerateRecipeRequest {
    @NotBlank
    private String dishName;

    public String getDishName() { return dishName; }
    public void setDishName(String dishName) { this.dishName = dishName; }
}

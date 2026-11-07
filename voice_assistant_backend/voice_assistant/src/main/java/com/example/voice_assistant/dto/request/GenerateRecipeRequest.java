package com.example.voice_assistant.dto.request;

import jakarta.validation.constraints.NotBlank;

public class GenerateRecipeRequest {
    @NotBlank
    private String dishName;

    /** Optional - links the saved recipe to this app user. */
    private String userId;

    public String getDishName() { return dishName; }
    public void setDishName(String dishName) { this.dishName = dishName; }
    public String getUserId() { return userId; }
    public void setUserId(String userId) { this.userId = userId; }
}

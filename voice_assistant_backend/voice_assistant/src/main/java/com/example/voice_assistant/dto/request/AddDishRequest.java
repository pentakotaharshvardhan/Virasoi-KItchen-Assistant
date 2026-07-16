package com.example.voice_assistant.dto.request;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;

public class AddDishRequest {
    @NotBlank
    private String dishName;

    @Min(1)
    private int servesRequested;

    public String getDishName() { return dishName; }
    public void setDishName(String dishName) { this.dishName = dishName; }
    public int getServesRequested() { return servesRequested; }
    public void setServesRequested(int servesRequested) { this.servesRequested = servesRequested; }
}

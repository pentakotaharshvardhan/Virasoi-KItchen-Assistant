package com.example.voice_assistant.dto.response;

import java.util.UUID;

public class DishSnapshotDto {
    public UUID sessionDishId;
    public String dishName;
    public String status;
    public int totalSteps;
    public int completedSteps;
}

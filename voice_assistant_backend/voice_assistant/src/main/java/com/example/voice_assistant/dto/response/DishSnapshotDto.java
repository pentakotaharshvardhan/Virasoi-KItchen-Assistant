package com.example.voice_assistant.dto.response;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

public class DishSnapshotDto {
    public UUID sessionDishId;
    public String dishName;
    public String status;
    public int totalSteps;
    public int completedSteps;
    public int currentStepIndex;
    /** Every step with its live status, so the UI renders a per-dish flow without another fetch. */
    public List<StepSnapshotDto> steps = new ArrayList<>();
}

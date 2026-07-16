package com.example.voice_assistant.dto.request;

import jakarta.validation.constraints.Min;

public class StartSessionRequest {
    /** Optional - ignored if present. The authenticated user (from the JWT) is always used instead. */
    private String userId;

    @Min(1)
    private int numberOfStoves;

    public String getUserId() { return userId; }
    public void setUserId(String userId) { this.userId = userId; }
    public int getNumberOfStoves() { return numberOfStoves; }
    public void setNumberOfStoves(int numberOfStoves) { this.numberOfStoves = numberOfStoves; }
}

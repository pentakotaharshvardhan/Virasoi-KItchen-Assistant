package com.example.voice_assistant.dto.response;

import java.util.UUID;

public class AuthResponse {
    public String token;
    public String tokenType = "Bearer";
    public long expiresInSeconds;
    public UUID userId;
    public String username;

    public AuthResponse() {}

    public AuthResponse(String token, long expiresInSeconds, UUID userId, String username) {
        this.token = token;
        this.expiresInSeconds = expiresInSeconds;
        this.userId = userId;
        this.username = username;
    }
}

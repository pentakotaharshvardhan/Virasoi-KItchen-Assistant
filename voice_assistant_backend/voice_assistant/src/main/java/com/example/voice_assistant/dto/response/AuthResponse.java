package com.example.voice_assistant.dto.response;

import java.util.UUID;

public class AuthResponse {
    public String token;
    public String tokenType = "Bearer";
    public long expiresInSeconds;
    public UUID userId;
    public String username;
    public String email;

    public AuthResponse() {}

    public AuthResponse(String token, long expiresInSeconds, UUID userId, String username) {
        this(token, expiresInSeconds, userId, username, null);
    }

    public AuthResponse(String token, long expiresInSeconds, UUID userId, String username, String email) {
        this.token = token;
        this.expiresInSeconds = expiresInSeconds;
        this.userId = userId;
        this.username = username;
        this.email = email;
    }
}

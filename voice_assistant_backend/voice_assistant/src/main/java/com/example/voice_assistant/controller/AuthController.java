package com.example.voice_assistant.controller;

import com.example.voice_assistant.dto.request.LoginRequest;
import com.example.voice_assistant.dto.request.RegisterRequest;
import com.example.voice_assistant.dto.response.AuthResponse;
import com.example.voice_assistant.service.AuthService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Login page endpoints for the Flutter app. Both return a JWT to send back as "Authorization: Bearer <token>". */
@RestController
@RequestMapping("/api/auth")
public class AuthController {

    private final AuthService authService;

    public AuthController(AuthService authService) {
        this.authService = authService;
    }

    @PostMapping("/register")
    public AuthResponse register(@Valid @RequestBody RegisterRequest request) {
        return authService.register(request);
    }

    @PostMapping("/login")
    public AuthResponse login(@Valid @RequestBody LoginRequest request) {
        return authService.login(request);
    }
}

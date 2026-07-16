package com.example.voice_assistant.config;

import com.example.voice_assistant.security.JwtHandshakeInterceptor;
import com.example.voice_assistant.security.JwtService;
import com.example.voice_assistant.service.CookingSessionService;
import com.example.voice_assistant.service.RecipeService;
import com.example.voice_assistant.service.SchedulerService;
import com.example.voice_assistant.service.SpeechToTextService;
import com.example.voice_assistant.service.TextToSpeechService;
import com.example.voice_assistant.websocket.AudioStreamWebSocketHandler;
import com.example.voice_assistant.websocket.WebSocketSessionRegistry;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.socket.config.annotation.EnableWebSocket;
import org.springframework.web.socket.config.annotation.WebSocketConfigurer;
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry;

@Configuration
@EnableWebSocket
public class WebSocketConfig implements WebSocketConfigurer {

    private final SpeechToTextService speechToTextService;
    private final TextToSpeechService textToSpeechService;
    private final RecipeService recipeService;
    private final CookingSessionService cookingSessionService;
    private final SchedulerService schedulerService;
    private final WebSocketSessionRegistry registry;
    private final ObjectMapper objectMapper;
    private final JwtService jwtService;

    public WebSocketConfig(SpeechToTextService speechToTextService, TextToSpeechService textToSpeechService,
                            RecipeService recipeService, CookingSessionService cookingSessionService,
                            SchedulerService schedulerService, WebSocketSessionRegistry registry,
                            ObjectMapper objectMapper, JwtService jwtService) {
        this.speechToTextService = speechToTextService;
        this.textToSpeechService = textToSpeechService;
        this.recipeService = recipeService;
        this.cookingSessionService = cookingSessionService;
        this.schedulerService = schedulerService;
        this.registry = registry;
        this.objectMapper = objectMapper;
        this.jwtService = jwtService;
    }

    @Override
    public void registerWebSocketHandlers(WebSocketHandlerRegistry registryConfig) {
        // /ws/audio?token=<jwt>&sessionId=<uuid> - JwtHandshakeInterceptor rejects the upgrade
        // (HTTP 401) before the handler ever sees the connection if the token is missing/invalid.
        registryConfig.addHandler(audioStreamWebSocketHandler(), "/ws/audio")
                .addInterceptors(new JwtHandshakeInterceptor(jwtService))
                .setAllowedOrigins("*");
    }

    private AudioStreamWebSocketHandler audioStreamWebSocketHandler() {
        return new AudioStreamWebSocketHandler(speechToTextService, textToSpeechService, recipeService,
                cookingSessionService, schedulerService, registry, objectMapper);
    }
}

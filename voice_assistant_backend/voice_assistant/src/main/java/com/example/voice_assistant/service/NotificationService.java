package com.example.voice_assistant.service;

import com.example.voice_assistant.dto.response.SessionSnapshotDto;
import com.example.voice_assistant.websocket.WebSocketSessionRegistry;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

import java.io.IOException;
import java.util.UUID;

/**
 * Pushes SessionSnapshotDto updates (current task, timer alerts, etc) to every WebSocket connected
 * to a session - and, since this is a *voice* assistant, synthesizes speech for the human-readable
 * `message` on every push so the Flutter app can just play `messageAudioBase64` instead of relying
 * on on-device TTS. Synthesis failure never blocks the push - the text `message` is always sent.
 */
@Service
public class NotificationService {

    private final WebSocketSessionRegistry registry;
    private final ObjectMapper objectMapper;
    private final TextToSpeechService textToSpeechService;

    public NotificationService(WebSocketSessionRegistry registry, ObjectMapper objectMapper,
                                TextToSpeechService textToSpeechService) {
        this.registry = registry;
        this.objectMapper = objectMapper;
        this.textToSpeechService = textToSpeechService;
    }

    public void pushSnapshot(UUID cookingSessionId, SessionSnapshotDto snapshot) {
        try {
            snapshot.messageAudioBase64 = textToSpeechService.synthesizeBase64(snapshot.message);
        } catch (Exception ignored) {
            // TextToSpeechService already swallows/logs its own failures and returns null; this is just a last resort.
        }

        try {
            String payload = objectMapper.writeValueAsString(new WsEnvelope("session_snapshot", snapshot));
            for (WebSocketSession ws : registry.get(cookingSessionId)) {
                if (ws.isOpen()) {
                    synchronized (ws) {
                        ws.sendMessage(new TextMessage(payload));
                    }
                }
            }
        } catch (IOException e) {
            throw new IllegalStateException("Failed to push session snapshot: " + e.getMessage(), e);
        }
    }

    /** Generic envelope so the Flutter client can switch on `type` for any message coming down the socket. */
    public record WsEnvelope(String type, Object data) {
    }
}

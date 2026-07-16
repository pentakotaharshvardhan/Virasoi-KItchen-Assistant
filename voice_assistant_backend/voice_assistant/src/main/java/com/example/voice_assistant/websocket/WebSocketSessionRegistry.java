package com.example.voice_assistant.websocket;

import org.springframework.stereotype.Component;
import org.springframework.web.socket.WebSocketSession;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;

/** Tracks live audio-WebSocket connections per cooking session so the backend can push events (timer done, next task, etc). */
@Component
public class WebSocketSessionRegistry {

    private final Map<UUID, List<WebSocketSession>> sessionsByCookingSessionId = new ConcurrentHashMap<>();

    public void register(UUID cookingSessionId, WebSocketSession webSocketSession) {
        sessionsByCookingSessionId
                .computeIfAbsent(cookingSessionId, k -> new CopyOnWriteArrayList<>())
                .add(webSocketSession);
    }

    public void unregister(UUID cookingSessionId, WebSocketSession webSocketSession) {
        List<WebSocketSession> list = sessionsByCookingSessionId.get(cookingSessionId);
        if (list != null) {
            list.remove(webSocketSession);
        }
    }

    public List<WebSocketSession> get(UUID cookingSessionId) {
        return sessionsByCookingSessionId.getOrDefault(cookingSessionId, List.of());
    }
}

package com.example.voice_assistant.websocket;

import org.springframework.stereotype.Component;
import org.springframework.web.socket.WebSocketSession;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicLong;

/** Tracks live audio-WebSocket connections per cooking session so the backend can push events (timer done, next task, etc). */
@Component
public class WebSocketSessionRegistry {

    private final Map<UUID, List<WebSocketSession>> sessionsByCookingSessionId = new ConcurrentHashMap<>();

    /** Monotonic sequence numbers stamped on every outgoing frame so a client can drop
     *  duplicates (a scheduler re-push, two sockets on one session, a replayed snapshot). */
    private final Map<String, AtomicLong> sequenceByChannel = new ConcurrentHashMap<>();

    public static String sessionChannel(UUID cookingSessionId) {
        return "session:" + cookingSessionId;
    }

    public long nextSeq(String channelKey) {
        return sequenceByChannel.computeIfAbsent(channelKey, k -> new AtomicLong()).incrementAndGet();
    }

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

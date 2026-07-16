package com.example.voice_assistant.security;

import org.springframework.http.server.ServerHttpRequest;
import org.springframework.http.server.ServerHttpResponse;
import org.springframework.http.server.ServletServerHttpRequest;
import org.springframework.web.socket.WebSocketHandler;
import org.springframework.web.socket.server.HandshakeInterceptor;

import java.util.Map;

/**
 * Authenticates the /ws/audio handshake. Browsers/mobile WebSocket clients can't set custom headers
 * on the upgrade request, so the JWT is passed as a query param instead: /ws/audio?token=<jwt>&sessionId=...
 * On success, the username/userId are stashed as WebSocketSession attributes for handlers to use.
 */
public class JwtHandshakeInterceptor implements HandshakeInterceptor {

    private final JwtService jwtService;

    public JwtHandshakeInterceptor(JwtService jwtService) {
        this.jwtService = jwtService;
    }

    @Override
    public boolean beforeHandshake(ServerHttpRequest request, ServerHttpResponse response,
                                    WebSocketHandler wsHandler, Map<String, Object> attributes) {
        String token = extractQueryParam(request, "token");

        if (token == null || !jwtService.isValid(token)) {
            response.setStatusCode(org.springframework.http.HttpStatus.UNAUTHORIZED);
            return false; // reject the handshake
        }

        attributes.put("username", jwtService.extractUsername(token));
        attributes.put("userId", jwtService.extractUserId(token));
        return true;
    }

    @Override
    public void afterHandshake(ServerHttpRequest request, ServerHttpResponse response,
                                WebSocketHandler wsHandler, Exception exception) {
        // no-op
    }

    private String extractQueryParam(ServerHttpRequest request, String key) {
        if (!(request instanceof ServletServerHttpRequest servletRequest)) return null;
        String query = servletRequest.getServletRequest().getQueryString();
        if (query == null) return null;
        for (String param : query.split("&")) {
            String[] kv = param.split("=", 2);
            if (kv.length == 2 && kv[0].equals(key)) {
                return java.net.URLDecoder.decode(kv[1], java.nio.charset.StandardCharsets.UTF_8);
            }
        }
        return null;
    }
}

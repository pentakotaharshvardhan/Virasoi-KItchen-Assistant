package com.example.voice_assistant.service;

import com.example.voice_assistant.dto.response.SessionSnapshotDto;
import com.example.voice_assistant.dto.response.UserTaskDto;
import com.example.voice_assistant.entity.RecipeIngredient;
import com.example.voice_assistant.entity.SessionDishStep;
import com.example.voice_assistant.repository.SessionDishStepRepository;
import com.example.voice_assistant.websocket.WebSocketSessionRegistry;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

import java.io.IOException;
import java.math.BigDecimal;
import java.util.Optional;
import java.util.UUID;

@Service
public class NotificationService {

    private final WebSocketSessionRegistry registry;
    private final ObjectMapper objectMapper;
    private final TextToSpeechService textToSpeechService;
    private final InstructionPersonalizationService instructionPersonalizationService;
    private final SessionDishStepRepository sessionDishStepRepository; // ADD

    public NotificationService(WebSocketSessionRegistry registry, ObjectMapper objectMapper,
                               TextToSpeechService textToSpeechService,
                               InstructionPersonalizationService instructionPersonalizationService,
                               SessionDishStepRepository sessionDishStepRepository) { // ADD param
        this.registry = registry;
        this.objectMapper = objectMapper;
        this.textToSpeechService = textToSpeechService;
        this.instructionPersonalizationService = instructionPersonalizationService;
        this.sessionDishStepRepository = sessionDishStepRepository; // ADD
    }

    public void pushSnapshot(UUID cookingSessionId, SessionSnapshotDto snapshot) {
        try {
            snapshot.message = personalize(snapshot);
        } catch (Exception ignored) {
            // fail-open: keep the scheduler's original message
        }

        try {
            snapshot.messageAudioBase64 = textToSpeechService.synthesizeBase64(snapshot.message);
        } catch (Exception ignored) {
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

    /**
     * Looks up the real SessionDishStep behind currentUserTask so the ingredient name, its
     * quantityPerServe/unit, and the dish's actual servesRequested can be passed to Gemini for a
     * genuine quantity calculation - not just a stove-number rewrite. Only recipes generated
     * AFTER the ingredientName/FK wiring was added will have a non-null ingredient here; older
     * steps simply fall back to stove-only personalization (or no change, if no stove either).
     * Safe to call mid-transaction: pushSnapshot() is always invoked synchronously from inside
     * an @Transactional SchedulerService method, so this repository read reuses that same
     * open Hibernate session (no LazyInitializationException risk).
     */
    private String personalize(SessionSnapshotDto snapshot) {
        if (snapshot.currentUserTask == null) return snapshot.message;
        UserTaskDto task = snapshot.currentUserTask;

        Integer stoveIndex = snapshot.stoves.stream()
                .filter(s -> task.stepId.equals(s.occupiedByStepId))
                .map(s -> s.stoveIndex)
                .findFirst().orElse(null);

        String ingredientName = null;
        BigDecimal quantityPerServe = null;
        String unit = null;
        int servesRequested = 1;

        Optional<SessionDishStep> stepOpt = sessionDishStepRepository.findById(task.stepId);
        if (stepOpt.isPresent()) {
            SessionDishStep step = stepOpt.get();
            servesRequested = step.getSessionDish().getServesRequested();
            RecipeIngredient ingredient = step.getIngredient();
            if (ingredient != null) {
                ingredientName = ingredient.getName();
                quantityPerServe = ingredient.getQuantityPerServe();
                unit = ingredient.getUnit();
            }
        }

        return instructionPersonalizationService.personalize(
                snapshot.message, ingredientName, quantityPerServe, unit, servesRequested, stoveIndex);
    }

    public record WsEnvelope(String type, Object data) {
    }
}
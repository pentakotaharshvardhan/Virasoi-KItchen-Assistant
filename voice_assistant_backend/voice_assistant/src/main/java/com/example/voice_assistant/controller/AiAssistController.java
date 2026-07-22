package com.example.voice_assistant.controller;


import com.example.voice_assistant.service.InstructionPersonalizationService;
import com.example.voice_assistant.service.VoiceCommandService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigDecimal;
import java.util.Map;

/**
 * Small AI-utility endpoints used by the voice pipeline. Both are stateless - nothing here is
 * persisted. The websocket handler calls VoiceCommandService directly (no HTTP round-trip);
 * these REST routes exist for the Flutter app's non-voice UI, debugging, and Postman testing.
 * Requires a valid JWT like every other non-/api/auth endpoint (see SecurityConfig).
 */
@RestController
public class AiAssistController {

    private final VoiceCommandService voiceCommandService;
    private final InstructionPersonalizationService instructionPersonalizationService;

    public AiAssistController(VoiceCommandService voiceCommandService,
                              InstructionPersonalizationService instructionPersonalizationService) {
        this.voiceCommandService = voiceCommandService;
        this.instructionPersonalizationService = instructionPersonalizationService;
    }

    @PostMapping("/api/ai/command")
    public Map<String, String> classifyCommand(@Valid @RequestBody ClassifyCommandRequest request) {
        VoiceCommandService.Command command = voiceCommandService.classify(request.transcript);
        return Map.of("command", command.name());
    }

    @PostMapping("/api/ai/personalize-instruction")
    public Map<String, String> personalizeInstruction(@Valid @RequestBody PersonalizeInstructionRequest request) {
        String text = instructionPersonalizationService.personalize(
                request.instruction,
                request.ingredientName,
                request.quantityPerServe,
                request.unit,
                request.servesRequested == null ? 1 : request.servesRequested,
                request.stoveIndex
        );
        return Map.of("text", text); // ephemeral - returned for immediate TTS use, never stored
    }

    public static class ClassifyCommandRequest {
        @NotBlank
        public String transcript;
    }

    public static class PersonalizeInstructionRequest {
        @NotBlank
        public String instruction;
        public String ingredientName;
        public BigDecimal quantityPerServe;
        public String unit;
        public Integer servesRequested;
        public Integer stoveIndex;
    }
}

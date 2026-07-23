package com.example.voice_assistant.controller;

import com.example.voice_assistant.dto.ai.VoiceCommandResultDto;
import com.example.voice_assistant.service.InstructionPersonalizationService;
import com.example.voice_assistant.service.VoiceCommandService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

@RestController
public class AiAssistController {

    private final VoiceCommandService voiceCommandService;
    private final InstructionPersonalizationService instructionPersonalizationService;

    public AiAssistController(VoiceCommandService voiceCommandService,
                              InstructionPersonalizationService instructionPersonalizationService) {
        this.voiceCommandService = voiceCommandService;
        this.instructionPersonalizationService = instructionPersonalizationService;
    }

    /** Classifies a transcript into command + stove/dish/ingredient/timer parameters. Used
     *  directly by the Ingredient screen (on-device STT -> POST here -> act on "REMOVE"
     *  locally); the live-session websocket calls VoiceCommandService directly instead. */
    @PostMapping("/api/ai/command")
    public VoiceCommandResultDto classifyCommand(@Valid @RequestBody ClassifyCommandRequest request) {
        return voiceCommandService.classify(request.transcript);
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
        return Map.of("text", text);
    }

    /** Dedicated Q&A for the standalone Help screen - always answers directly, no classification. */
    @PostMapping("/api/ai/help")
    public Map<String, String> help(@Valid @RequestBody HelpQuestionRequest request) {
        return Map.of("answer", voiceCommandService.answerHelpQuestion(request.question));
    }

    /** Reference list of example phrases per command, so the Help screen can show users exactly
     *  what to say instead of hardcoding a second copy of the list in Flutter. */
    @GetMapping("/api/ai/help/commands")
    public List<VoiceCommandService.CommandExample> commandReference() {
        return VoiceCommandService.CANONICAL_EXAMPLES;
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

    public static class HelpQuestionRequest {
        @NotBlank
        public String question;
    }
}


package com.example.voice_assistant.service;

import com.example.voice_assistant.properties.AiProperties;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;

import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Classifies a raw voice transcript into exactly ONE command word using Gemini's lightweight
 * `gemini-3.1-flash-lite` model. Replaces naive keyword matching (transcript.contains("done"))
 * so paraphrased/noisy STT output ("okay I'm done with that one") still routes correctly.
 *
 * Deliberately separate from AiFormattingService's recipe-generation calls: no JSON mode, no
 * schema, minimal tokens - this is on the hot path of every spoken command in a live session.
 */
@Service
public class VoiceCommandService {

    private static final String CLASSIFIER_INSTRUCTION = """
            You are a strict voice-command classifier for a hands-free cooking assistant.
            Read the user's spoken sentence (it may be noisy speech-to-text output) and reply with
            EXACTLY ONE WORD from this fixed list, in uppercase, nothing else - no punctuation,
            no explanation, no quotes:

            NEXT      - user confirms current step is done / wants to move on ("done", "finished", "next", "go ahead")
            WAIT      - user wants to hold before moving on ("wait", "not yet", "hold on", "give me a minute")
            TIMER_YES - user wants a timer started ("yes", "sure", "start a timer", "yes 5 minutes")
            TIMER_NO  - user declines a timer ("no", "no thanks", "skip it")
            REPEAT    - user wants the last instruction repeated ("repeat", "say that again", "what did you say")
            STOP      - user wants to end/pause the session ("stop", "cancel", "end session", "pause everything")
            UNKNOWN   - anything that doesn't clearly match one of the above

            Reply with only the single word.
            """;

    private final WebClient.Builder webClientBuilder;
    private final AiProperties aiProperties;
    private final ObjectMapper objectMapper;

    public VoiceCommandService(WebClient.Builder webClientBuilder, AiProperties aiProperties, ObjectMapper objectMapper) {
        this.webClientBuilder = webClientBuilder;
        this.aiProperties = aiProperties;
        this.objectMapper = objectMapper;
    }

    public enum Command { NEXT, WAIT, TIMER_YES, TIMER_NO, REPEAT, STOP, UNKNOWN }

    /** Never throws - any Gemini/parsing failure falls back to UNKNOWN so a live session never breaks. */
    public Command classify(String transcript) {
        if (transcript == null || transcript.isBlank()) return Command.UNKNOWN;

        try {
            Map<String, Object> body = new LinkedHashMap<>();
            body.put("system_instruction", Map.of("parts", List.of(Map.of("text", CLASSIFIER_INSTRUCTION))));
            body.put("contents", List.of(Map.of("role", "user", "parts", List.of(Map.of("text", transcript)))));
            body.put("generationConfig", Map.of("temperature", 0.0, "maxOutputTokens", 5));

            WebClient client = webClientBuilder.baseUrl(aiProperties.getBaseUrl()).build();

            String rawJson = client.post()
                    .uri(uriBuilder -> uriBuilder
                            .path("/models/{model}:generateContent")
                            .queryParam("key", aiProperties.getApiKey())
                            .build(aiProperties.getModel()))
                    .header("Content-Type", "application/json")
                    .bodyValue(body)
                    .retrieve()
                    .bodyToMono(String.class)
                    .block(Duration.ofSeconds(Math.min(aiProperties.getTimeoutSeconds(), 10)));

            JsonNode root = objectMapper.readTree(rawJson);
            String text = root.path("candidates").path(0).path("content").path("parts").path(0).path("text").asText("");
            String word = text.trim().replaceAll("[^A-Za-z_]", "").toUpperCase();
            return Command.valueOf(word);
        } catch (Exception e) {
            return Command.UNKNOWN;
        }
    }
}
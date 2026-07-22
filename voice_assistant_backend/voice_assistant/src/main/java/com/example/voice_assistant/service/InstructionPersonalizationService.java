package com.example.voice_assistant.service;


import com.example.voice_assistant.properties.AiProperties;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;

import java.math.BigDecimal;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Rewrites a raw recipe-step instruction into one natural, spoken sentence for TTS, computing the
 * actual required quantity from `quantityPerServe * servesRequested` and mentioning the assigned
 * stove number, when given.
 *
 * IMPORTANT: pure request/response transformation. The result is used ONLY for the one TTS call
 * it was requested for and is NEVER written to the database or any entity.
 */
@Service
public class InstructionPersonalizationService {

    private static final String SYSTEM_INSTRUCTION = """
            You are rewriting a cooking instruction into ONE natural, friendly, spoken sentence for
            text-to-speech. You will be given: the raw instruction text; the ingredient name, its
            quantity PER SERVE, and its unit (may be absent); how many serves are being cooked; and
            which stove number this is happening on (may be absent for non-stove steps).

            Compute the actual required quantity using this exact formula:
                totalQuantity = quantityPerServe * servesRequested

            Rewrite the instruction to naturally include the computed totalQuantity + unit (rounded
            to at most 2 decimal places, dropping trailing zeros) in place of any generic amount, and
            mention "on stove <N>" if a stove number is given. Keep it one short, warm, conversational
            sentence - not robotic. Reply with ONLY the final sentence: no quotes, no markdown, no
            explanation, no restating the inputs.
            """;

    private final WebClient.Builder webClientBuilder;
    private final AiProperties aiProperties;
    private final ObjectMapper objectMapper;

    public InstructionPersonalizationService(WebClient.Builder webClientBuilder, AiProperties aiProperties,
                                             ObjectMapper objectMapper) {
        this.webClientBuilder = webClientBuilder;
        this.aiProperties = aiProperties;
        this.objectMapper = objectMapper;
    }

    /**
     * @return the rewritten sentence, or {@code rawInstruction} unchanged if anything fails
     *         (a personalization outage must never block a live cooking session).
     */
    public String personalize(String rawInstruction, String ingredientName, BigDecimal quantityPerServe,
                              String unit, int servesRequested, Integer stoveIndex) {
        if (rawInstruction == null || rawInstruction.isBlank()) return rawInstruction;

        try {
            Map<String, Object> inputs = new LinkedHashMap<>();
            inputs.put("instruction", rawInstruction);
            inputs.put("ingredientName", ingredientName);
            inputs.put("quantityPerServe", quantityPerServe);
            inputs.put("unit", unit);
            inputs.put("servesRequested", servesRequested);
            inputs.put("stoveIndex", stoveIndex);
            String userPrompt = objectMapper.writeValueAsString(inputs);

            Map<String, Object> body = new LinkedHashMap<>();
            body.put("system_instruction", Map.of("parts", List.of(Map.of("text", SYSTEM_INSTRUCTION))));
            body.put("contents", List.of(Map.of("role", "user", "parts", List.of(Map.of("text", userPrompt)))));
            body.put("generationConfig", Map.of("temperature", 0.3, "maxOutputTokens", 120));

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
            String cleaned = text.trim().replaceAll("^\"|\"$", ""); // strip stray wrapping quotes, if any
            return cleaned.isEmpty() ? rawInstruction : cleaned;
        } catch (Exception e) {
            return rawInstruction; // fail-open
        }
    }
}

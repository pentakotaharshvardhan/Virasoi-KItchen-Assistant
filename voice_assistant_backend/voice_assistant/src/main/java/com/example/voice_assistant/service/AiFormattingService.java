package com.example.voice_assistant.service;

import com.example.voice_assistant.dto.ai.AiRecipeResponseDto;
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
 * Talks to Google's Gemini API (`gemini-3.5-flash` by default) to:
 *   1) turn a raw ancestor-recipe voice transcript into strict structured JSON, and
 *   2) generate a brand-new recipe from scratch when a requested dish isn't in the DB.
 *
 * Gemini Flash models are on Google's free tier (rate-limited, see AI Studio for current caps),
 * which is why this replaced the paid OpenAI chat-completions call. Uses `responseMimeType:
 * "application/json"` so Gemini returns pure JSON with no markdown fences to strip.
 */
@Service
public class AiFormattingService {

    private static final String JSON_SCHEMA_INSTRUCTIONS = """
        You are a professional recipe editor for a cooking assistant app.
        Always respond with ONLY a single valid JSON object - no markdown fences, no commentary.
        The JSON object MUST match exactly this shape:
        {
          "dishName": string,
          "description": string,
          "ingredients": [
            { "name": string, "quantityPerServe": number, "unit": string }
          ],
          "steps": [
            {
              "stepNumber": integer starting at 1,
              "instruction": string (clear, single action, spoken-friendly),
              "stepType": one of "STOVE" | "USER_ACTION" | "PASSIVE",
              "requiresTimer": boolean,
              "timerSeconds": integer or null,
              "scalesWithServes": boolean,
              "ingredientName": string or null
            }
          ]
        }

        Rules:
        - All quantities and timer durations must be scoped to exactly ONE (1) serve/person.
        - Always start from cutting/peeling/soaking task of ingredients ,if there is a need of that step
        - "STOVE" = needs a stove/burner (frying, boiling, simmering, roasting).
        - "USER_ACTION" = needs the cook's hands but no stove (chopping, whisking, kneading, plating, marinated mixing).
        - "PASSIVE" = needs nobody actively right now (resting dough, marinating in the fridge, cooling).
        - Set requiresTimer=true and provide timerSeconds whenever a step has a natural duration (boil 10 min -> 600).
        - Set scalesWithServes=true only for timers that meaningfully grow with more food (e.g. boiling a bigger pot),
          and false for fixed-duration steps (e.g. resting dough 10 minutes regardless of quantity).
        - Set "ingredientName" to the EXACT string used in one of the "ingredients[].name" entries above when this
          step measures out or adds that specific ingredient (e.g. step "Add the salt" -> ingredientName: "salt",
          matching ingredients[].name exactly). Set it to null when the step has no single specific ingredient
          (e.g. "heat the pan", "plate and serve", "let it rest").
        """;

    private final WebClient.Builder webClientBuilder;
    private final AiProperties aiProperties;
    private final ObjectMapper objectMapper;

    public AiFormattingService(WebClient.Builder webClientBuilder, AiProperties aiProperties, ObjectMapper objectMapper) {
        this.webClientBuilder = webClientBuilder;
        this.aiProperties = aiProperties;
        this.objectMapper = objectMapper;
    }

    /** Formats a raw voice transcript of a family/ancestor recipe into structured JSON. */
    public AiFormattingResult formatAncestorRecipe(String rawTranscript, String dishNameHint) {
        String userPrompt = """
                Format the following home-cooked family recipe transcript into the required JSON shape.
                It may be informal, out of order, or missing exact quantities - use your best culinary judgement
                to fill gaps sensibly while staying faithful to what was described.
                Dish name hint (may be empty): %s
                ---
                Transcript:
                %s
                """.formatted(dishNameHint == null ? "" : dishNameHint, rawTranscript);

        return callGeminiForRecipe(userPrompt);
    }

    /** Generates a brand-new recipe from scratch for a dish name that wasn't found in the DB. */
    public AiFormattingResult generateRecipe(String dishName) {
        String userPrompt = """
                Create a complete, authentic, step-by-step recipe for the dish: "%s".
                Return it in the required JSON shape, scoped to exactly one (1) serve.
                """.formatted(dishName);

        return callGeminiForRecipe(userPrompt);
    }

    private AiFormattingResult callGeminiForRecipe(String userPrompt) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("system_instruction", Map.of("parts", List.of(Map.of("text", JSON_SCHEMA_INSTRUCTIONS))));
        body.put("contents", List.of(Map.of("role", "user", "parts", List.of(Map.of("text", userPrompt)))));
        body.put("generationConfig", Map.of(
                "temperature", 0.4,
                "responseMimeType", "application/json"
        ));

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
                .block(Duration.ofSeconds(aiProperties.getTimeoutSeconds()));

        try {
            JsonNode root = objectMapper.readTree(rawJson);
            String content = root.path("candidates").path(0).path("content").path("parts").path(0).path("text").asText();
            AiRecipeResponseDto parsed = objectMapper.readValue(content, AiRecipeResponseDto.class);
            return new AiFormattingResult(parsed, content);
        } catch (Exception e) {
            throw new IllegalStateException("Failed to parse Gemini recipe response: " + e.getMessage() + " | raw=" + rawJson, e);
        }
    }

    /** Bundles the parsed recipe alongside the raw JSON text (kept for audit in Recipe.rawAiJson). */
    public record AiFormattingResult(AiRecipeResponseDto recipe, String rawJson) {
    }
}

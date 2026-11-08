package com.example.voice_assistant.service;

import com.example.voice_assistant.dto.ai.VoiceCommandResultDto;
import com.example.voice_assistant.properties.AiProperties;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.web.reactive.function.client.ClientResponse;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

class VoiceCommandServiceTest {

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Test
    void removeReturnsOnlyCanonicalChecklistNamesForMultipleMisspellings() throws Exception {
        VoiceCommandService service = serviceFor(modelResult("REMOVE", List.of("panner"), null));

        VoiceCommandResultDto result = service.classify(
                "remove panner and onions", List.of("Paneer", "Onions", "Tomato"));

        assertEquals("REMOVE", result.command);
        assertEquals(List.of("Paneer", "Onions"), result.ingredientNames);
        assertEquals("Paneer", result.ingredientName);
    }

    @Test
    void removeMatchesAWordInsideACompoundChecklistName() throws Exception {
        VoiceCommandService service = serviceFor(modelResult("REMOVE", List.of("paneer"), null));

        VoiceCommandResultDto result = service.classify(
                "remove paneer", List.of("Cheesy Paneer", "Tomatoes"));

        assertEquals(List.of("Cheesy Paneer"), result.ingredientNames);
    }

    @Test
    void ambiguousIngredientSpellingDoesNotSelectEitherChecklistName() throws Exception {
        VoiceCommandService service = serviceFor(modelResult("REMOVE", List.of("panner"), null));

        VoiceCommandResultDto result = service.classify(
                "remove panner", List.of("Cheesy Paneer", "Spicy Paneer"));

        assertEquals(List.of(), result.ingredientNames);
        assertNull(result.ingredientName);
    }

    @Test
    void nextDeduplicatesAllNamedStoves() throws Exception {
        VoiceCommandService service = serviceFor(
                modelResult("NEXT", null, List.of(1, 1, 2)));

        VoiceCommandResultDto result = service.classify(
                "stoves 1 and 2 are free", List.of());

        assertEquals("NEXT", result.command);
        assertEquals(List.of(1, 2), result.stoveIndices);
        assertEquals(1, result.stoveIndex);
    }

    @Test
    void ruleBasedFallbackRecognizesFreeUserSeparatelyFromStoveCompletion() throws Exception {
        VoiceCommandService service = serviceFor(modelResult("UNKNOWN", null, null));

        VoiceCommandResultDto user = service.classify("I am free", List.of());
        VoiceCommandResultDto stove = service.classify("stoves 1 and 2 are free", List.of());

        assertEquals("FREE_USER", user.command);
        assertEquals("NEXT", stove.command);
        assertEquals(List.of(1, 2), stove.stoveIndices);
    }

    private VoiceCommandService serviceFor(String modelJson) {
        WebClient.Builder webClientBuilder = WebClient.builder()
                .exchangeFunction(request -> Mono.just(
                        ClientResponse.create(HttpStatus.OK)
                                .header("Content-Type", "application/json")
                                .body(modelJson)
                                .build()));
        AiProperties properties = new AiProperties();
        properties.setBaseUrl("https://ai.example.test");
        properties.setApiKey("test");
        properties.setModel("test-model");
        properties.setTimeoutSeconds(1);
        return new VoiceCommandService(webClientBuilder, properties, objectMapper);
    }

    private String modelResult(String command, List<String> ingredients, List<Integer> stoveIndices)
            throws Exception {
        Map<String, Object> result = Map.of(
                "command", command,
                "ingredientNames", ingredients == null ? List.of() : ingredients,
                "stoveIndices", stoveIndices == null ? List.of() : stoveIndices);
        String text = objectMapper.writeValueAsString(result);
        return objectMapper.writeValueAsString(Map.of(
                "candidates", List.of(Map.of(
                        "content", Map.of(
                                "parts", List.of(Map.of("text", text)))))));
    }
}

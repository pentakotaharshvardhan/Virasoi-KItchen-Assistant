package com.example.voice_assistant.service;

import com.example.voice_assistant.properties.TtsProperties;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;

import java.time.Duration;
import java.util.Map;

/**
 * Default TTS implementation: Google Cloud Text-to-Speech v1 REST API, authenticated with a
 * simple API key. Uses a *Standard* voice (hi-IN-Standard-A by default) rather than WaveNet/Neural2
 * because Standard voices sit in Google's much larger free monthly character quota.
 */
@Service
public class GoogleCloudTextToSpeechService implements TextToSpeechService {

    private static final Logger log = LoggerFactory.getLogger(GoogleCloudTextToSpeechService.class);

    private final WebClient.Builder webClientBuilder;
    private final TtsProperties ttsProperties;
    private final ObjectMapper objectMapper;

    public GoogleCloudTextToSpeechService(WebClient.Builder webClientBuilder, TtsProperties ttsProperties, ObjectMapper objectMapper) {
        this.webClientBuilder = webClientBuilder;
        this.ttsProperties = ttsProperties;
        this.objectMapper = objectMapper;
    }

    @Override
    public String synthesizeBase64(String text) {
        if (text == null || text.isBlank()) {
            return null;
        }
        try {
            Map<String, Object> body = Map.of(
                    "input", Map.of("text", text),
                    "voice", Map.of(
                            "languageCode", ttsProperties.getLanguageCode(),
                            "name", ttsProperties.getVoiceName()
                    ),
                    "audioConfig", Map.of("audioEncoding", ttsProperties.getAudioEncoding())
            );

            WebClient client = webClientBuilder.baseUrl(ttsProperties.getBaseUrl()).build();

            String rawJson = client.post()
                    .uri(uriBuilder -> uriBuilder.path("/text:synthesize").queryParam("key", ttsProperties.getApiKey()).build())
                    .header("Content-Type", "application/json")
                    .bodyValue(body)
                    .retrieve()
                    .bodyToMono(String.class)
                    .block(Duration.ofSeconds(ttsProperties.getTimeoutSeconds()));

            JsonNode root = objectMapper.readTree(rawJson);
            String audioContent = root.path("audioContent").asText(null);
            return (audioContent == null || audioContent.isBlank()) ? null : audioContent;
        } catch (Exception e) {
            // Speech is a nice-to-have on top of the text response - never let TTS take the whole request down.
            log.warn("TTS synthesis failed, continuing with text-only response: {}", e.getMessage());
            return null;
        }
    }
}

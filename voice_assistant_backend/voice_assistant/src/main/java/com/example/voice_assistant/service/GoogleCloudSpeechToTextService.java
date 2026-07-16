package com.example.voice_assistant.service;

import com.example.voice_assistant.properties.SttProperties;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;

import java.time.Duration;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Default STT implementation: Google Cloud Speech-to-Text v1 REST API (`speech:recognize`),
 * authenticated with a simple API key (no service-account JSON needed). Google gives ~60 minutes
 * of free standard-model recognition per month, which is why this replaced the paid Whisper call.
 *
 * IMPORTANT: the client must record audio in the format configured below (default LINEAR16 /
 * 16kHz mono WAV/PCM) - Google's REST API needs an explicit encoding, it can't sniff the format
 * the way Whisper's multipart upload could. Adjust `stt.audio-encoding` / `stt.sample-rate-hertz`
 * in application.yml to match whatever your Flutter recorder actually produces (e.g. WEBM_OPUS).
 */
@Service
public class GoogleCloudSpeechToTextService implements SpeechToTextService {

    private final WebClient.Builder webClientBuilder;
    private final SttProperties sttProperties;
    private final ObjectMapper objectMapper;

    public GoogleCloudSpeechToTextService(WebClient.Builder webClientBuilder, SttProperties sttProperties, ObjectMapper objectMapper) {
        this.webClientBuilder = webClientBuilder;
        this.sttProperties = sttProperties;
        this.objectMapper = objectMapper;
    }

    @Override
    public String transcribe(byte[] audioBytes, String fileNameHint) {
        if (audioBytes == null || audioBytes.length == 0) {
            return "";
        }

        Map<String, Object> config = new LinkedHashMap<>();
        config.put("encoding", sttProperties.getAudioEncoding());
        config.put("sampleRateHertz", sttProperties.getSampleRateHertz());
        config.put("languageCode", sttProperties.getLanguageCode());
        config.put("enableAutomaticPunctuation", true);

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("config", config);
        body.put("audio", Map.of("content", Base64.getEncoder().encodeToString(audioBytes)));

        WebClient client = webClientBuilder.baseUrl(sttProperties.getBaseUrl()).build();

        String rawJson = client.post()
                .uri(uriBuilder -> uriBuilder.path("/speech:recognize").queryParam("key", sttProperties.getApiKey()).build())
                .header("Content-Type", "application/json")
                .bodyValue(body)
                .retrieve()
                .bodyToMono(String.class)
                .block(Duration.ofSeconds(sttProperties.getTimeoutSeconds()));

        try {
            JsonNode root = objectMapper.readTree(rawJson);
            JsonNode results = root.path("results");
            if (!results.isArray() || results.isEmpty()) {
                return "";
            }
            StringBuilder transcript = new StringBuilder();
            for (JsonNode result : results) {
                String piece = result.path("alternatives").path(0).path("transcript").asText("");
                if (!piece.isBlank()) {
                    if (transcript.length() > 0) transcript.append(" ");
                    transcript.append(piece.trim());
                }
            }
            return transcript.toString();
        } catch (Exception e) {
            throw new IllegalStateException("Failed to parse Google STT response: " + e.getMessage() + " | raw=" + rawJson, e);
        }
    }
}

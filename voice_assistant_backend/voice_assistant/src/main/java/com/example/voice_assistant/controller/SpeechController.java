package com.example.voice_assistant.controller;

import com.example.voice_assistant.service.SpeechToTextService;
import com.example.voice_assistant.service.TextToSpeechService;
import jakarta.validation.constraints.NotBlank;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.util.Map;

/**
 * REST fallback for one-shot speech-to-text/text-to-speech (e.g. the Flutter app already recorded
 * a full clip instead of streaming). The main "continuous listening" experience uses /ws/audio,
 * which also pushes synthesized speech alongside every prompt/session snapshot automatically.
 */
@RestController
public class SpeechController {

    private final SpeechToTextService speechToTextService;
    private final TextToSpeechService textToSpeechService;

    public SpeechController(SpeechToTextService speechToTextService, TextToSpeechService textToSpeechService) {
        this.speechToTextService = speechToTextService;
        this.textToSpeechService = textToSpeechService;
    }

    @PostMapping(value = "/api/speech/transcribe", consumes = "multipart/form-data")
    public Map<String, String> transcribe(@RequestParam("file") MultipartFile file) throws IOException {
        String text = speechToTextService.transcribe(file.getBytes(), file.getOriginalFilename());
        return Map.of("text", text);
    }

    /** Returns Base64-encoded MP3 audio (Google Cloud TTS, Hindi Standard voice by default) for the given text. */
    @PostMapping(value = "/api/speech/synthesize")
    public Map<String, String> synthesize(@RequestBody SynthesizeRequest request) {
        String audioBase64 = textToSpeechService.synthesizeBase64(request.text);
        return audioBase64 == null ? Map.of() : Map.of("audioBase64", audioBase64, "audioEncoding", "MP3");
    }

    public static class SynthesizeRequest {
        @NotBlank
        public String text;
    }
}

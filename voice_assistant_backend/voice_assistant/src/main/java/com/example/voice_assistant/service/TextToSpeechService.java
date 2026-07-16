package com.example.voice_assistant.service;

/** Abstraction over whatever TTS provider is behind it - so callers don't care that it's Google Cloud TTS. */
public interface TextToSpeechService {
    /**
     * Synthesizes speech for the given text.
     * @return Base64-encoded audio (format per TtsProperties.audioEncoding, default MP3),
     *         ready to drop straight into a JSON payload for the Flutter app to decode + play.
     *         Returns null if synthesis fails - callers should treat speech as optional and never
     *         let a TTS failure block the underlying text response.
     */
    String synthesizeBase64(String text);
}

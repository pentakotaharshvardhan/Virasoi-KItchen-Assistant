package com.example.voice_assistant.service;

/**
 * Abstraction over whatever speech-to-text provider is behind it, so the WebSocket handler
 * doesn't care whether it's Google Cloud STT, Azure Speech, Deepgram, etc.
 * Swap the implementation bean (see GoogleCloudSpeechToTextService, the default) to change providers.
 */
public interface SpeechToTextService {

    /**
     * Transcribes one complete buffered utterance of raw audio bytes.
     * @param audioBytes raw audio, matching the encoding configured in application.yml (stt.audio-encoding)
     * @param fileNameHint a filename hint (unused by the Google Cloud implementation, kept for interface flexibility)
     * @return the transcribed text (may be empty if nothing understandable was said)
     */
    String transcribe(byte[] audioBytes, String fileNameHint);
}

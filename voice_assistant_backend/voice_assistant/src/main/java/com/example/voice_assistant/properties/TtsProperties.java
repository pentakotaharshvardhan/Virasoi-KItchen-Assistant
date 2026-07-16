package com.example.voice_assistant.properties;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "tts")
public class TtsProperties {
    private String baseUrl;
    private String apiKey;
    /** "hi-IN" for Hindi by default - Standard voices (not WaveNet/Neural2) sit in Google's larger free monthly quota. */
    private String languageCode = "hi-IN";
    private String voiceName = "hi-IN-Standard-A";
    private String audioEncoding = "MP3";
    private int timeoutSeconds = 30;

    public String getBaseUrl() { return baseUrl; }
    public void setBaseUrl(String baseUrl) { this.baseUrl = baseUrl; }
    public String getApiKey() { return apiKey; }
    public void setApiKey(String apiKey) { this.apiKey = apiKey; }
    public String getLanguageCode() { return languageCode; }
    public void setLanguageCode(String languageCode) { this.languageCode = languageCode; }
    public String getVoiceName() { return voiceName; }
    public void setVoiceName(String voiceName) { this.voiceName = voiceName; }
    public String getAudioEncoding() { return audioEncoding; }
    public void setAudioEncoding(String audioEncoding) { this.audioEncoding = audioEncoding; }
    public int getTimeoutSeconds() { return timeoutSeconds; }
    public void setTimeoutSeconds(int timeoutSeconds) { this.timeoutSeconds = timeoutSeconds; }
}

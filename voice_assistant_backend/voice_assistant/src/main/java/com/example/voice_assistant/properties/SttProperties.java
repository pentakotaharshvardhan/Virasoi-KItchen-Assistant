package com.example.voice_assistant.properties;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "stt")
public class SttProperties {
    private String baseUrl;
    private String apiKey;
    /** Recognition language for Google Cloud STT, e.g. "en-IN" or "hi-IN". */
    private String languageCode = "en-IN";
    /** Audio encoding of the bytes the client sends: LINEAR16, WEBM_OPUS, MP3, FLAC, etc. */
    private String audioEncoding = "LINEAR16";
    private int sampleRateHertz = 16000;
    private int timeoutSeconds = 30;

    public String getBaseUrl() { return baseUrl; }
    public void setBaseUrl(String baseUrl) { this.baseUrl = baseUrl; }
    public String getApiKey() { return apiKey; }
    public void setApiKey(String apiKey) { this.apiKey = apiKey; }
    public String getLanguageCode() { return languageCode; }
    public void setLanguageCode(String languageCode) { this.languageCode = languageCode; }
    public String getAudioEncoding() { return audioEncoding; }
    public void setAudioEncoding(String audioEncoding) { this.audioEncoding = audioEncoding; }
    public int getSampleRateHertz() { return sampleRateHertz; }
    public void setSampleRateHertz(int sampleRateHertz) { this.sampleRateHertz = sampleRateHertz; }
    public int getTimeoutSeconds() { return timeoutSeconds; }
    public void setTimeoutSeconds(int timeoutSeconds) { this.timeoutSeconds = timeoutSeconds; }
}

package com.example.voice_assistant.properties;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "ai")
public class AiProperties {
    private String baseUrl;
    private String apiKey;
    private String model;
    /**
     * The contextual helper is the only call that may carry an image (the screen screenshot).
     * A lite text model can reject inline images, and screenshot prompts are slower, so the
     * helper gets its own (multimodal) model and timeout.
     */
    private String helperModel = "gemini-3.1-flash-lite";
    private int helperTimeoutSeconds = 25;
    /** Interactive calls (classify/help/personalize): fail over to local logic quickly. */
    private int timeoutSeconds = 10;
    /** Recipe formatting/generation is a long single AI call - give Gemini room to answer. */
    private int generationTimeoutSeconds = 60;

    public String getBaseUrl() { return baseUrl; }
    public void setBaseUrl(String baseUrl) { this.baseUrl = baseUrl; }
    public String getApiKey() { return apiKey; }
    public void setApiKey(String apiKey) { this.apiKey = apiKey; }
    public String getModel() { return model; }
    public void setModel(String model) { this.model = model; }
    public String getHelperModel() { return helperModel; }
    public void setHelperModel(String helperModel) { this.helperModel = helperModel; }
    public int getHelperTimeoutSeconds() { return helperTimeoutSeconds; }
    public void setHelperTimeoutSeconds(int helperTimeoutSeconds) {
        this.helperTimeoutSeconds = helperTimeoutSeconds;
    }
    public int getTimeoutSeconds() { return timeoutSeconds; }
    public void setTimeoutSeconds(int timeoutSeconds) { this.timeoutSeconds = timeoutSeconds; }
    public int getGenerationTimeoutSeconds() { return generationTimeoutSeconds; }
    public void setGenerationTimeoutSeconds(int generationTimeoutSeconds) {
        this.generationTimeoutSeconds = generationTimeoutSeconds;
    }
}

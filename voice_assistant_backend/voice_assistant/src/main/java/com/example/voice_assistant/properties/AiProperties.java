package com.example.voice_assistant.properties;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "ai")
public class AiProperties {
    private String baseUrl;
    private String apiKey;
    private String model;
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
    public int getTimeoutSeconds() { return timeoutSeconds; }
    public void setTimeoutSeconds(int timeoutSeconds) { this.timeoutSeconds = timeoutSeconds; }
    public int getGenerationTimeoutSeconds() { return generationTimeoutSeconds; }
    public void setGenerationTimeoutSeconds(int generationTimeoutSeconds) {
        this.generationTimeoutSeconds = generationTimeoutSeconds;
    }
}

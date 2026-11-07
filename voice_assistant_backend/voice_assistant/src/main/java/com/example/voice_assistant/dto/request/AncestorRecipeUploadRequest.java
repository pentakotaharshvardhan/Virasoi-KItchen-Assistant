package com.example.voice_assistant.dto.request;

import jakarta.validation.constraints.NotBlank;

/** Fallback REST path for uploading an ancestor recipe as plain transcript text (voice path uses the /ws/audio WebSocket instead). */
public class AncestorRecipeUploadRequest {

    @NotBlank
    private String transcriptText;

    private String dishNameHint;

    private String createdBy;

    /** Optional - links the saved recipe to this app user. */
    private String userId;

    public String getTranscriptText() { return transcriptText; }
    public void setTranscriptText(String transcriptText) { this.transcriptText = transcriptText; }
    public String getDishNameHint() { return dishNameHint; }
    public void setDishNameHint(String dishNameHint) { this.dishNameHint = dishNameHint; }
    public String getCreatedBy() { return createdBy; }
    public void setCreatedBy(String createdBy) { this.createdBy = createdBy; }
    public String getUserId() { return userId; }
    public void setUserId(String userId) { this.userId = userId; }
}

package com.example.voice_assistant.dto.request;

import com.example.voice_assistant.properties.KitchenLimits;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;

import java.util.List;

public class GenerateRecipeBatchRequest {

    /** Dishes the user wants to cook; each one is generated as its own standalone recipe. */
    @NotEmpty
    @Size(max = KitchenLimits.MAX_DISHES, message = "dishNames must not contain more than 4 dishes")
    private List<@NotBlank String> dishNames;

    /** Optional - links every saved recipe to this app user. */
    private String userId;

    public List<String> getDishNames() { return dishNames; }
    public void setDishNames(List<String> dishNames) { this.dishNames = dishNames; }
    public String getUserId() { return userId; }
    public void setUserId(String userId) { this.userId = userId; }
}

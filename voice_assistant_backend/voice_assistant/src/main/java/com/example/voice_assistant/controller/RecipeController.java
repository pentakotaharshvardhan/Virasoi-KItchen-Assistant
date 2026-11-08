package com.example.voice_assistant.controller;

import com.example.voice_assistant.dto.request.AncestorRecipeUploadRequest;
import com.example.voice_assistant.dto.request.GenerateRecipeBatchRequest;
import com.example.voice_assistant.dto.request.GenerateRecipeRequest;
import com.example.voice_assistant.entity.Recipe;
import com.example.voice_assistant.exception.ResourceNotFoundException;
import com.example.voice_assistant.security.AppUserDetails;
import com.example.voice_assistant.service.RecipeService;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.UUID;

/**
 * Recipe endpoints. The primary "ancestor recipe" and "find dish" flows normally happen over the
 * /ws/audio WebSocket (continuous voice), but every step is also exposed here as plain REST so the
 * Flutter app (or Postman) can drive/test the same logic with typed text instead of voice.
 */
@RestController
@RequestMapping("/api/recipes")
public class RecipeController {

    private final RecipeService recipeService;

    public RecipeController(RecipeService recipeService) {
        this.recipeService = recipeService;
    }

    @GetMapping
    public List<Recipe> listAll(Authentication authentication) {
        return recipeService.listByUserId(authenticatedUserId(authentication));
    }

    /** Recipes added by one user only (the app's recipe list screen uses this). */
    @GetMapping("/user/{userId}")
    public List<Recipe> listByUser(@PathVariable String userId, Authentication authentication) {
        if (!authenticatedUserId(authentication).equals(userId)) {
            throw new AccessDeniedException("Recipes can only be listed for the signed-in user.");
        }
        return recipeService.listByUserId(userId);
    }

    @GetMapping("/{id}")
    public Recipe getById(@PathVariable UUID id) {
        return recipeService.getById(id);
    }

    @GetMapping("/search")
    public Recipe search(@RequestParam String dishName) {
        return recipeService.findByDishName(dishName)
                .orElseThrow(() -> new ResourceNotFoundException("No recipe found for \"" + dishName + "\""));
    }

    /** find-or-generate: looks the dish up, and if it's missing, asks the AI to create + save it on the spot. */
    @PostMapping("/find-or-generate")
    public Recipe findOrGenerate(
            @Valid @RequestBody GenerateRecipeRequest request, Authentication authentication) {
        return recipeService.findOrGenerate(request.getDishName(), authenticatedUserId(authentication));
    }

    /** Forces a fresh AI-generated recipe even if one already exists (e.g. user wants a different variation). */
    @PostMapping("/generate")
    public Recipe generate(
            @Valid @RequestBody GenerateRecipeRequest request, Authentication authentication) {
        return recipeService.generateAndSaveRecipe(request.getDishName(), authenticatedUserId(authentication));
    }

    /**
     * Multi-dish meal in one go: dishes already in the DB are reused from their stored JSON; only the
     * missing ones are sent to the AI, in a single call that returns one standalone (never combined)
     * recipe per dish. Every recipe is saved individually.
     */
    @PostMapping("/generate-batch")
    public List<Recipe> generateBatch(
            @Valid @RequestBody GenerateRecipeBatchRequest request, Authentication authentication) {
        return recipeService.generateOrReuseRecipes(
                request.getDishNames(), authenticatedUserId(authentication));
    }

    /** REST fallback for uploading an ancestor recipe from already-transcribed text. */
    @PostMapping("/ancestor")
    public ResponseEntity<Recipe> uploadAncestorRecipe(
            @Valid @RequestBody AncestorRecipeUploadRequest request, Authentication authentication) {
        Recipe saved = recipeService.uploadAncestorRecipe(
                request.getTranscriptText(), request.getDishNameHint(), request.getCreatedBy(),
                authenticatedUserId(authentication));
        return ResponseEntity.ok(saved);
    }

    private String authenticatedUserId(Authentication authentication) {
        Object principal = authentication == null ? null : authentication.getPrincipal();
        if (principal instanceof AppUserDetails user) return user.getId().toString();
        throw new AccessDeniedException("A signed-in user is required.");
    }
}

package com.example.voice_assistant.controller;

import com.example.voice_assistant.dto.request.AncestorRecipeUploadRequest;
import com.example.voice_assistant.dto.request.GenerateRecipeRequest;
import com.example.voice_assistant.entity.Recipe;
import com.example.voice_assistant.exception.ResourceNotFoundException;
import com.example.voice_assistant.service.RecipeService;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
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
    public List<Recipe> listAll() {
        return recipeService.listAll();
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
    public Recipe findOrGenerate(@Valid @RequestBody GenerateRecipeRequest request) {
        return recipeService.findOrGenerate(request.getDishName());
    }

    /** Forces a fresh AI-generated recipe even if one already exists (e.g. user wants a different variation). */
    @PostMapping("/generate")
    public Recipe generate(@Valid @RequestBody GenerateRecipeRequest request) {
        return recipeService.generateAndSaveRecipe(request.getDishName());
    }

    /** REST fallback for uploading an ancestor recipe from already-transcribed text. */
    @PostMapping("/ancestor")
    public ResponseEntity<Recipe> uploadAncestorRecipe(@Valid @RequestBody AncestorRecipeUploadRequest request) {
        Recipe saved = recipeService.uploadAncestorRecipe(request.getTranscriptText(), request.getDishNameHint(), request.getCreatedBy());
        return ResponseEntity.ok(saved);
    }
}

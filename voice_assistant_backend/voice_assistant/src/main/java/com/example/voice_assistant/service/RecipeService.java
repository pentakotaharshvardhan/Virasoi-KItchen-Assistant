package com.example.voice_assistant.service;

import com.example.voice_assistant.dto.ai.AiIngredientDto;
import com.example.voice_assistant.dto.ai.AiRecipeResponseDto;
import com.example.voice_assistant.dto.ai.AiStepDto;
import com.example.voice_assistant.entity.Recipe;
import com.example.voice_assistant.entity.RecipeIngredient;
import com.example.voice_assistant.entity.RecipeStep;
import com.example.voice_assistant.entity.enums.RecipeSource;
import com.example.voice_assistant.entity.enums.StepType;
import com.example.voice_assistant.exception.ResourceNotFoundException;
import com.example.voice_assistant.repository.RecipeRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.Map;
import java.util.stream.Collectors;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Service
public class RecipeService {

    private final RecipeRepository recipeRepository;
    private final AiFormattingService aiFormattingService;

    public RecipeService(RecipeRepository recipeRepository, AiFormattingService aiFormattingService) {
        this.recipeRepository = recipeRepository;
        this.aiFormattingService = aiFormattingService;
    }

    public static String normalize(String dishName) {
        return dishName == null ? "" : dishName.trim().toLowerCase().replaceAll("\\s+", " ");
    }

    public Optional<Recipe> findByDishName(String dishName) {
        return recipeRepository.findByDishNameNormalized(normalize(dishName));
    }

    public Recipe getById(UUID id) {
        return recipeRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Recipe not found: " + id));
    }

    public List<Recipe> listAll() {
        return recipeRepository.findAll();
    }

    /** Formats a raw ancestor-recipe transcript via AI and persists it. */
    @Transactional
    public Recipe uploadAncestorRecipe(String rawTranscript, String dishNameHint, String createdBy) {
        AiFormattingService.AiFormattingResult result = aiFormattingService.formatAncestorRecipe(rawTranscript, dishNameHint);
        return saveFromAi(result, RecipeSource.ANCESTOR, createdBy);
    }

    /** Generates a brand-new recipe via AI (used when a requested dish isn't found) and persists it. */
    @Transactional
    public Recipe generateAndSaveRecipe(String dishName) {
        AiFormattingService.AiFormattingResult result = aiFormattingService.generateRecipe(dishName);
        return saveFromAi(result, RecipeSource.AI_GENERATED, "AI");
    }

    /** Looks a dish up in the DB; if missing, asks the AI to generate + persist a new one. Core "find or create" flow. */
    @Transactional
    public Recipe findOrGenerate(String dishName) {
        return findByDishName(dishName).orElseGet(() -> generateAndSaveRecipe(dishName));
    }

    private Recipe saveFromAi(AiFormattingService.AiFormattingResult result, RecipeSource source, String createdBy) {
        AiRecipeResponseDto ai = result.recipe();
        if (ai.dishName == null || ai.dishName.isBlank()) {
            throw new IllegalStateException("AI response did not include a dish name");
        }

        String normalized = normalize(ai.dishName);
        Recipe recipe = recipeRepository.findByDishNameNormalized(normalized).orElseGet(Recipe::new);

        recipe.setDishName(ai.dishName);
        recipe.setDishNameNormalized(normalized);
        recipe.setDescription(ai.description);
        recipe.setBaseServes(1);
        recipe.setSource(source);
        recipe.setCreatedBy(createdBy);
        recipe.setRawAiJson(result.rawJson());

        recipe.getIngredients().clear();
        for (AiIngredientDto i : ai.ingredients) {
            recipe.addIngredient(new RecipeIngredient(i.name, BigDecimal.valueOf(i.quantityPerServe), i.unit));
        }

        // Lookup so steps can be linked to the ingredient they measure out (case/whitespace-insensitive,
        // reusing the same normalize() used for dish names). ADD this block.
        Map<String, RecipeIngredient> ingredientsByName = recipe.getIngredients().stream()
                .collect(Collectors.toMap(ri -> normalize(ri.getName()), ri -> ri, (a, b) -> a));

        recipe.getSteps().clear();
        for (AiStepDto s : ai.steps) {
            RecipeStep step = new RecipeStep();
            step.setStepNumber(s.stepNumber);
            step.setInstruction(s.instruction);
            step.setStepType(parseStepType(s.stepType));
            step.setRequiresTimer(s.requiresTimer);
            step.setBaseTimerSeconds(s.timerSeconds);
            step.setScalesWithServes(s.scalesWithServes);
            if (s.ingredientName != null && !s.ingredientName.isBlank()) {   // ADD
                step.setIngredient(ingredientsByName.get(normalize(s.ingredientName))); // ADD
            }
            recipe.addStep(step);
        }

        return recipeRepository.save(recipe);
    }

    private StepType parseStepType(String raw) {
        if (raw == null) return StepType.USER_ACTION;
        try {
            return StepType.valueOf(raw.trim().toUpperCase());
        } catch (IllegalArgumentException e) {
            return StepType.USER_ACTION;
        }
    }
}

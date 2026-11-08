package com.example.voice_assistant.service;

import com.example.voice_assistant.dto.ai.AiIngredientDto;
import com.example.voice_assistant.dto.ai.AiRecipeResponseDto;
import com.example.voice_assistant.dto.ai.AiStepDto;
import com.example.voice_assistant.entity.Recipe;
import com.example.voice_assistant.entity.RecipeIngredient;
import com.example.voice_assistant.entity.RecipeStep;
import com.example.voice_assistant.entity.UserRecipe;
import com.example.voice_assistant.entity.enums.RecipeSource;
import com.example.voice_assistant.entity.enums.StepType;
import com.example.voice_assistant.exception.ResourceNotFoundException;
import com.example.voice_assistant.properties.KitchenLimits;
import com.example.voice_assistant.repository.RecipeRepository;
import com.example.voice_assistant.repository.UserRecipeRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
public class RecipeService {

    private final RecipeRepository recipeRepository;
    private final UserRecipeRepository userRecipeRepository;
    private final AiFormattingService aiFormattingService;

    public RecipeService(RecipeRepository recipeRepository, UserRecipeRepository userRecipeRepository,
                         AiFormattingService aiFormattingService) {
        this.recipeRepository = recipeRepository;
        this.userRecipeRepository = userRecipeRepository;
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

    /** Every recipe saved by the given app user, newest first. */
    @Transactional
    public List<Recipe> listByUserId(String userId) {
        // Backfill links for recipes saved under the legacy single-owner column.
        recipeRepository.findByUserId(userId).forEach(recipe -> linkToUser(recipe, userId));
        return recipeRepository.findRecipesForUser(userId);
    }

    /** Formats a raw ancestor-recipe transcript via AI and persists it. */
    @Transactional
    public Recipe uploadAncestorRecipe(String rawTranscript, String dishNameHint, String createdBy) {
        return uploadAncestorRecipe(rawTranscript, dishNameHint, createdBy, null);
    }

    /** Formats a raw ancestor-recipe transcript via AI and persists it for the given user. */
    @Transactional
    public Recipe uploadAncestorRecipe(String rawTranscript, String dishNameHint, String createdBy, String userId) {
        AiFormattingService.AiFormattingResult result = aiFormattingService.formatAncestorRecipe(rawTranscript, dishNameHint);
        return saveFromAi(result, RecipeSource.ANCESTOR, createdBy, userId);
    }

    /** Generates a brand-new recipe via AI (used when a requested dish isn't found) and persists it. */
    @Transactional
    public Recipe generateAndSaveRecipe(String dishName) {
        return generateAndSaveRecipe(dishName, null);
    }

    /** Generates a brand-new recipe via AI and persists it for the given user. */
    @Transactional
    public Recipe generateAndSaveRecipe(String dishName, String userId) {
        AiFormattingService.AiFormattingResult result = aiFormattingService.generateRecipe(dishName);
        return saveFromAi(result, RecipeSource.AI_GENERATED, "AI", userId);
    }

    /** Looks a dish up in the DB; if missing, asks the AI to generate + persist a new one. Core "find or create" flow. */
    @Transactional
    public Recipe findOrGenerate(String dishName) {
        return findOrGenerate(dishName, null);
    }

    /** Looks a dish up in the DB for the given user; if missing, asks the AI to generate + persist it. */
    @Transactional
    public Recipe findOrGenerate(String dishName, String userId) {
        Optional<Recipe> existing = findByDishName(dishName);
        if (existing.isPresent()) {
            linkToUser(existing.get(), userId);
            return existing.get();
        }
        return generateAndSaveRecipe(dishName, userId);
    }

    /** Records that the user has added/made this recipe, so it shows up in their own list. */
    private void linkToUser(Recipe recipe, String userId) {
        if (recipe == null || userId == null || userId.isBlank()) return;
        if (!userRecipeRepository.existsByUserIdAndRecipeId(userId, recipe.getId())) {
            userRecipeRepository.save(new UserRecipe(userId, recipe));
        }
    }

    /**
     * Multi-dish meal generation: checks the DB FIRST and reuses the stored JSON for any dish that
     * already exists, then asks Gemini in ONE call for independent (never combined/combo) recipes
     * for the remaining dishes only. Each generated recipe is saved as its own row.
     *
     * @return the recipes in the same order the dishes were requested.
     */
    @Transactional
    public List<Recipe> generateOrReuseRecipes(List<String> dishNames, String userId) {
        List<String> requested = dishNames == null ? List.of() : dishNames.stream()
                .filter(name -> name != null && !name.isBlank())
                .map(String::trim)
                .distinct()
                .toList();
        if (requested.size() > KitchenLimits.MAX_DISHES) {
            throw new IllegalArgumentException("A meal can contain at most " + KitchenLimits.MAX_DISHES + " dishes");
        }

        Map<String, Recipe> resolved = new LinkedHashMap<>();
        List<String> missing = new ArrayList<>();

        // 1. Already in the DB? Reuse its stored JSON and just link it to this user.
        for (String name : requested) {
            Optional<Recipe> existing = findByDishName(name);
            if (existing.isPresent()) {
                linkToUser(existing.get(), userId);
                resolved.put(normalize(name), existing.get());
            } else {
                missing.add(name);
            }
        }

        // 2. Ask the AI only for the dishes that are missing, all in a single call.
        if (!missing.isEmpty()) {
            AiFormattingService.AiBatchFormattingResult batch = aiFormattingService.generateRecipes(missing);
            Map<String, AiRecipeResponseDto> generatedByName = new HashMap<>();
            if (batch.recipes() != null) {
                for (AiRecipeResponseDto dto : batch.recipes()) {
                    if (dto != null && dto.dishName != null && !dto.dishName.isBlank()) {
                        generatedByName.putIfAbsent(normalize(dto.dishName), dto);
                    }
                }
            }

            for (String name : missing) {
                AiRecipeResponseDto dto = generatedByName.get(normalize(name));
                Recipe saved;
                if (dto != null) {
                    saved = saveFromAi(dto, RecipeSource.AI_GENERATED, "AI", userId, batch.rawJson());
                } else {
                    // AI skipped/renamed this one: fall back to a single-dish call so the meal still works.
                    saved = generateAndSaveRecipe(name, userId);
                }
                resolved.put(normalize(name), saved);
            }
        }

        // 3. Keep the order the user asked for.
        List<Recipe> ordered = new ArrayList<>();
        for (String name : requested) {
            Recipe recipe = resolved.get(normalize(name));
            if (recipe != null) {
                ordered.add(recipe);
            }
        }
        return ordered;
    }

    private Recipe saveFromAi(AiFormattingService.AiFormattingResult result, RecipeSource source,
                              String createdBy, String userId) {
        return saveFromAi(result.recipe(), source, createdBy, userId, result.rawJson());
    }

    private Recipe saveFromAi(AiRecipeResponseDto ai, RecipeSource source,
                              String createdBy, String userId, String rawJson) {
        if (ai == null || ai.dishName == null || ai.dishName.isBlank()) {
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
        // Keep the original owner if the dish already exists.
        if (userId != null && !userId.isBlank() && recipe.getUserId() == null) {
            recipe.setUserId(userId);
        }
        recipe.setRawAiJson(rawJson);

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

        Recipe saved = recipeRepository.save(recipe);
        linkToUser(saved, userId);
        return saved;
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

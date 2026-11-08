package com.example.voice_assistant.service;

import com.example.voice_assistant.repository.RecipeRepository;
import com.example.voice_assistant.repository.UserRecipeRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;

class RecipeServiceLimitTest {

    private RecipeRepository recipeRepository;
    private UserRecipeRepository userRecipeRepository;
    private AiFormattingService aiFormattingService;
    private RecipeService recipeService;

    @BeforeEach
    void setUp() {
        recipeRepository = mock(RecipeRepository.class);
        userRecipeRepository = mock(UserRecipeRepository.class);
        aiFormattingService = mock(AiFormattingService.class);
        recipeService = new RecipeService(recipeRepository, userRecipeRepository, aiFormattingService);
    }

    @Test
    void batchGenerationRejectsMoreThanFourUniqueDishesBeforeDatabaseOrAiCalls() {
        assertThrows(IllegalArgumentException.class, () -> recipeService.generateOrReuseRecipes(
                List.of("Dish one", "Dish two", "Dish three", "Dish four", "Dish five"),
                "user-1"));

        verifyNoInteractions(recipeRepository, userRecipeRepository, aiFormattingService);
    }
}

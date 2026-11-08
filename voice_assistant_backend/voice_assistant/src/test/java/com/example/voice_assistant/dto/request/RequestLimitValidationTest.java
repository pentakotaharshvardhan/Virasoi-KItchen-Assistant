package com.example.voice_assistant.dto.request;

import jakarta.validation.Validation;
import jakarta.validation.Validator;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertFalse;

class RequestLimitValidationTest {

    private final Validator validator = Validation.buildDefaultValidatorFactory().getValidator();

    @Test
    void startSessionRequestRejectsMoreThanFourStoves() {
        StartSessionRequest request = new StartSessionRequest();
        request.setNumberOfStoves(5);

        assertFalse(validator.validate(request).isEmpty());
    }

    @Test
    void batchRecipeRequestRejectsMoreThanFourDishes() {
        GenerateRecipeBatchRequest request = new GenerateRecipeBatchRequest();
        request.setDishNames(List.of("Dish one", "Dish two", "Dish three", "Dish four", "Dish five"));

        assertFalse(validator.validate(request).isEmpty());
    }
}

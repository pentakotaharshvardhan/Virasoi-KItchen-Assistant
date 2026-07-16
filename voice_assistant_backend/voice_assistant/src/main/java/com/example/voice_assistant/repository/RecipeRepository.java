package com.example.voice_assistant.repository;

import com.example.voice_assistant.entity.Recipe;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

public interface RecipeRepository extends JpaRepository<Recipe, UUID> {
    Optional<Recipe> findByDishNameNormalized(String dishNameNormalized);
    boolean existsByDishNameNormalized(String dishNameNormalized);
}

package com.example.voice_assistant.repository;

import com.example.voice_assistant.entity.UserRecipe;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

public interface UserRecipeRepository extends JpaRepository<UserRecipe, UUID> {
    boolean existsByUserIdAndRecipeId(String userId, UUID recipeId);
}

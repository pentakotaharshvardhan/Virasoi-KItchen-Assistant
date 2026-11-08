package com.example.voice_assistant.repository;

import com.example.voice_assistant.entity.Recipe;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface RecipeRepository extends JpaRepository<Recipe, UUID> {
    Optional<Recipe> findByDishNameNormalized(String dishNameNormalized);
    boolean existsByDishNameNormalized(String dishNameNormalized);

    /** Legacy owner column - used to backfill user_recipes links for recipes saved before that table existed. */
    List<Recipe> findByUserId(String userId);

    /** Recipes linked to the given app user (via user_recipes), newest first. */
    @Query("select ur.recipe from UserRecipe ur where ur.userId = :userId order by ur.recipe.createdAt desc")
    List<Recipe> findRecipesForUser(@Param("userId") String userId);
}

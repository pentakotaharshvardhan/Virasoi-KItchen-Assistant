package com.example.voice_assistant.entity;

import jakarta.persistence.*;

import java.time.Instant;
import java.util.UUID;

/**
 * Links a recipe to an app user. A recipe's content is still stored once per dish
 * (the recipes table keeps its unique dish-name constraint), while this table
 * records which users added/made that recipe so each user only sees their own list.
 */
@Entity
@Table(name = "user_recipes",
        uniqueConstraints = @UniqueConstraint(name = "uk_user_recipe", columnNames = {"user_id", "recipe_id"}))
public class UserRecipe {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "user_id", nullable = false)
    private String userId;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "recipe_id", nullable = false)
    private Recipe recipe;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt = Instant.now();

    public UserRecipe() {
    }

    public UserRecipe(String userId, Recipe recipe) {
        this.userId = userId;
        this.recipe = recipe;
    }

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }
    public String getUserId() { return userId; }
    public void setUserId(String userId) { this.userId = userId; }
    public Recipe getRecipe() { return recipe; }
    public void setRecipe(Recipe recipe) { this.recipe = recipe; }
    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }
}

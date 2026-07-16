package com.example.voice_assistant.entity;

import com.example.voice_assistant.entity.enums.RecipeSource;
import jakarta.persistence.*;
import com.fasterxml.jackson.databind.annotation.JsonSerialize;
import com.fasterxml.jackson.databind.ser.std.ToStringSerializer;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@Entity
@Table(name = "recipes")
public class Recipe {

    @Id
    @GeneratedValue
    private UUID id;

    /** Normalized (lower-cased, trimmed) dish name used for fast lookups when a user asks to cook something. */
    @Column(name = "dish_name", nullable = false)
    private String dishName;

    @Column(name = "dish_name_normalized", nullable = false, unique = true)
    private String dishNameNormalized;

    @Column(columnDefinition = "TEXT")
    private String description;

    /** All quantities/timers on child steps/ingredients are expressed for this many serves (always 1 today). */
    @Column(name = "base_serves", nullable = false)
    private int baseServes = 1;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private RecipeSource source;

    /** Who contributed it, e.g. "Grandma Meena" for an ancestor recipe, or "AI" for generated ones. */
    @Column(name = "created_by")
    private String createdBy;

    /** Raw JSON returned by the AI, kept for audit/debugging purposes. */
    @Column(name = "raw_ai_json", columnDefinition = "TEXT")
    private String rawAiJson;

    @Column(name = "created_at", nullable = false, updatable = false)
    @JsonSerialize(using = ToStringSerializer.class)
    private Instant createdAt = Instant.now();

    @OneToMany(mappedBy = "recipe", cascade = CascadeType.ALL, orphanRemoval = true, fetch = FetchType.EAGER)
    @OrderBy("id ASC")
    private List<RecipeIngredient> ingredients = new ArrayList<>();

    @OneToMany(mappedBy = "recipe", cascade = CascadeType.ALL, orphanRemoval = true, fetch = FetchType.EAGER)
    @OrderBy("stepNumber ASC")
    private List<RecipeStep> steps = new ArrayList<>();

    public Recipe() {
    }

    public void addIngredient(RecipeIngredient ingredient) {
        ingredient.setRecipe(this);
        this.ingredients.add(ingredient);
    }

    public void addStep(RecipeStep step) {
        step.setRecipe(this);
        this.steps.add(step);
    }

    // ---- getters / setters ----
    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }
    public String getDishName() { return dishName; }
    public void setDishName(String dishName) { this.dishName = dishName; }
    public String getDishNameNormalized() { return dishNameNormalized; }
    public void setDishNameNormalized(String dishNameNormalized) { this.dishNameNormalized = dishNameNormalized; }
    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description; }
    public int getBaseServes() { return baseServes; }
    public void setBaseServes(int baseServes) { this.baseServes = baseServes; }
    public RecipeSource getSource() { return source; }
    public void setSource(RecipeSource source) { this.source = source; }
    public String getCreatedBy() { return createdBy; }
    public void setCreatedBy(String createdBy) { this.createdBy = createdBy; }
    public String getRawAiJson() { return rawAiJson; }
    public void setRawAiJson(String rawAiJson) { this.rawAiJson = rawAiJson; }
    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }
    public List<RecipeIngredient> getIngredients() { return ingredients; }
    public void setIngredients(List<RecipeIngredient> ingredients) { this.ingredients = ingredients; }
    public List<RecipeStep> getSteps() { return steps; }
    public void setSteps(List<RecipeStep> steps) { this.steps = steps; }
}

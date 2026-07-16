package com.example.voice_assistant.entity;

import com.fasterxml.jackson.annotation.JsonIgnore;
import jakarta.persistence.*;

import java.math.BigDecimal;
import java.util.UUID;

@Entity
@Table(name = "recipe_ingredients")
public class RecipeIngredient {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(nullable = false)
    private String name;

    /** Quantity needed for exactly `recipe.baseServes` (1) serve. */
    @Column(name = "quantity_per_serve", nullable = false, precision = 12, scale = 3)
    private BigDecimal quantityPerServe;

    /** e.g. g, kg, ml, l, tsp, tbsp, cup, piece */
    private String unit;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "recipe_id")
    @JsonIgnore
    private Recipe recipe;

    public RecipeIngredient() {
    }

    public RecipeIngredient(String name, BigDecimal quantityPerServe, String unit) {
        this.name = name;
        this.quantityPerServe = quantityPerServe;
        this.unit = unit;
    }

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public BigDecimal getQuantityPerServe() { return quantityPerServe; }
    public void setQuantityPerServe(BigDecimal quantityPerServe) { this.quantityPerServe = quantityPerServe; }
    public String getUnit() { return unit; }
    public void setUnit(String unit) { this.unit = unit; }
    public Recipe getRecipe() { return recipe; }
    public void setRecipe(Recipe recipe) { this.recipe = recipe; }
}

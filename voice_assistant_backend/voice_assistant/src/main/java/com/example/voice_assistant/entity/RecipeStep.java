package com.example.voice_assistant.entity;

import com.example.voice_assistant.entity.enums.StepType;
import com.fasterxml.jackson.annotation.JsonIgnore;
import jakarta.persistence.*;

import java.util.UUID;

@Entity
@Table(name = "recipe_steps")
public class RecipeStep {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "step_number", nullable = false)
    private int stepNumber;

    @Column(columnDefinition = "TEXT", nullable = false)
    private String instruction;

    @Enumerated(EnumType.STRING)
    @Column(name = "step_type", nullable = false)
    private StepType stepType;

    @Column(name = "requires_timer", nullable = false)
    private boolean requiresTimer;

    /** Timer length in seconds for 1 serve (baseServes). Null when requiresTimer is false. */
    @Column(name = "base_timer_seconds")
    private Integer baseTimerSeconds;

    /** Whether this step's timer should grow when cooking for more people (e.g. boiling more rice takes longer). */
    @Column(name = "scales_with_serves", nullable = false)
    private boolean scalesWithServes = false;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "recipe_id")
    @JsonIgnore
    private Recipe recipe;

    public RecipeStep() {
    }

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }
    public int getStepNumber() { return stepNumber; }
    public void setStepNumber(int stepNumber) { this.stepNumber = stepNumber; }
    public String getInstruction() { return instruction; }
    public void setInstruction(String instruction) { this.instruction = instruction; }
    public StepType getStepType() { return stepType; }
    public void setStepType(StepType stepType) { this.stepType = stepType; }
    public boolean isRequiresTimer() { return requiresTimer; }
    public void setRequiresTimer(boolean requiresTimer) { this.requiresTimer = requiresTimer; }
    public Integer getBaseTimerSeconds() { return baseTimerSeconds; }
    public void setBaseTimerSeconds(Integer baseTimerSeconds) { this.baseTimerSeconds = baseTimerSeconds; }
    public boolean isScalesWithServes() { return scalesWithServes; }
    public void setScalesWithServes(boolean scalesWithServes) { this.scalesWithServes = scalesWithServes; }
    public Recipe getRecipe() { return recipe; }
    public void setRecipe(Recipe recipe) { this.recipe = recipe; }
}

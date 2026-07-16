package com.example.voice_assistant.entity;

import com.example.voice_assistant.entity.enums.DishStatus;
import com.fasterxml.jackson.annotation.JsonIgnore;
import jakarta.persistence.*;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/** A single dish being cooked within a session, with its own copy of scaled steps. */
@Entity
@Table(name = "session_dishes")
public class SessionDish {

    @Id
    @GeneratedValue
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "session_id", nullable = false)
    @JsonIgnore
    private CookingSession session;

    /** Source recipe this dish was scaled from (nullable for fully ad-hoc dishes). */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "recipe_id")
    private Recipe recipe;

    @Column(name = "dish_name", nullable = false)
    private String dishName;

    @Column(name = "serves_requested", nullable = false)
    private int servesRequested;

    /** Order in which dishes were added to the session; used as a fair, FCFS tie-breaker by the scheduler. */
    @Column(name = "priority_order", nullable = false)
    private int priorityOrder;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private DishStatus status = DishStatus.PENDING;

    /** Index into `steps` (ordered by stepNumber) pointing at the current/next step to work on. */
    @Column(name = "current_step_index", nullable = false)
    private int currentStepIndex = 0;

    @OneToMany(mappedBy = "sessionDish", cascade = CascadeType.ALL, orphanRemoval = true, fetch = FetchType.EAGER)
    @OrderBy("stepNumber ASC")
    private List<SessionDishStep> steps = new ArrayList<>();

    public SessionDish() {
    }

    public void addStep(SessionDishStep step) {
        step.setSessionDish(this);
        this.steps.add(step);
    }

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }
    public CookingSession getSession() { return session; }
    public void setSession(CookingSession session) { this.session = session; }
    public Recipe getRecipe() { return recipe; }
    public void setRecipe(Recipe recipe) { this.recipe = recipe; }
    public String getDishName() { return dishName; }
    public void setDishName(String dishName) { this.dishName = dishName; }
    public int getServesRequested() { return servesRequested; }
    public void setServesRequested(int servesRequested) { this.servesRequested = servesRequested; }
    public int getPriorityOrder() { return priorityOrder; }
    public void setPriorityOrder(int priorityOrder) { this.priorityOrder = priorityOrder; }
    public DishStatus getStatus() { return status; }
    public void setStatus(DishStatus status) { this.status = status; }
    public int getCurrentStepIndex() { return currentStepIndex; }
    public void setCurrentStepIndex(int currentStepIndex) { this.currentStepIndex = currentStepIndex; }
    public List<SessionDishStep> getSteps() { return steps; }
    public void setSteps(List<SessionDishStep> steps) { this.steps = steps; }
}

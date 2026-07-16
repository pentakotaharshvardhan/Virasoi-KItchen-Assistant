package com.example.voice_assistant.entity;

import com.example.voice_assistant.entity.enums.StepStatus;
import com.example.voice_assistant.entity.enums.StepType;
import com.fasterxml.jackson.annotation.JsonIgnore;
import jakarta.persistence.*;
import com.fasterxml.jackson.databind.annotation.JsonSerialize;
import com.fasterxml.jackson.databind.ser.std.ToStringSerializer;

import java.time.Instant;
import java.util.UUID;

/** A per-session, per-dish, servings-scaled instance of a RecipeStep. This is what the scheduler actually moves around. */
@Entity
@Table(name = "session_dish_steps")
public class SessionDishStep {

    @Id
    @GeneratedValue
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "session_dish_id", nullable = false)
    @JsonIgnore
    private SessionDish sessionDish;

    @Column(name = "step_number", nullable = false)
    private int stepNumber;

    @Column(columnDefinition = "TEXT", nullable = false)
    private String instruction;

    @Enumerated(EnumType.STRING)
    @Column(name = "step_type", nullable = false)
    private StepType stepType;

    @Column(name = "requires_timer", nullable = false)
    private boolean requiresTimer;

    /** Timer length in seconds, already scaled for this dish's servesRequested. */
    @Column(name = "timer_seconds")
    private Integer timerSeconds;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private StepStatus status = StepStatus.PENDING;

    /** Which stove (1-based index) this step was assigned to, if stepType == STOVE and it's in progress. */
    @Column(name = "assigned_stove_index")
    private Integer assignedStoveIndex;

    @Column(name = "timer_start_at")
    @JsonSerialize(using = ToStringSerializer.class)
    private Instant timerStartAt;

    @Column(name = "timer_end_at")
    @JsonSerialize(using = ToStringSerializer.class)
    private Instant timerEndAt;

    public SessionDishStep() {
    }

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }
    public SessionDish getSessionDish() { return sessionDish; }
    public void setSessionDish(SessionDish sessionDish) { this.sessionDish = sessionDish; }
    public int getStepNumber() { return stepNumber; }
    public void setStepNumber(int stepNumber) { this.stepNumber = stepNumber; }
    public String getInstruction() { return instruction; }
    public void setInstruction(String instruction) { this.instruction = instruction; }
    public StepType getStepType() { return stepType; }
    public void setStepType(StepType stepType) { this.stepType = stepType; }
    public boolean isRequiresTimer() { return requiresTimer; }
    public void setRequiresTimer(boolean requiresTimer) { this.requiresTimer = requiresTimer; }
    public Integer getTimerSeconds() { return timerSeconds; }
    public void setTimerSeconds(Integer timerSeconds) { this.timerSeconds = timerSeconds; }
    public StepStatus getStatus() { return status; }
    public void setStatus(StepStatus status) { this.status = status; }
    public Integer getAssignedStoveIndex() { return assignedStoveIndex; }
    public void setAssignedStoveIndex(Integer assignedStoveIndex) { this.assignedStoveIndex = assignedStoveIndex; }
    public Instant getTimerStartAt() { return timerStartAt; }
    public void setTimerStartAt(Instant timerStartAt) { this.timerStartAt = timerStartAt; }
    public Instant getTimerEndAt() { return timerEndAt; }
    public void setTimerEndAt(Instant timerEndAt) { this.timerEndAt = timerEndAt; }
}

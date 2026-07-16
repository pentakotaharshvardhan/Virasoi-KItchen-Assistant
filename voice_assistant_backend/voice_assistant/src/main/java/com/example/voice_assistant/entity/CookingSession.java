package com.example.voice_assistant.entity;

import com.example.voice_assistant.entity.enums.SessionStatus;
import com.fasterxml.jackson.annotation.JsonIgnore;
import jakarta.persistence.*;
import com.fasterxml.jackson.databind.annotation.JsonSerialize;
import com.fasterxml.jackson.databind.ser.std.ToStringSerializer;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/**
 * One cooking "sitting" for a user: they tell us how many stoves they have,
 * then add one or more dishes to cook. The SchedulerService is the brain
 * that juggles all dishes in a session across the available stoves and the
 * single user resource.
 */
@Entity
@Table(name = "cooking_sessions")
public class CookingSession {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "user_id", nullable = false)
    private String userId;

    @Column(name = "number_of_stoves", nullable = false)
    private int numberOfStoves;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private SessionStatus status = SessionStatus.ACTIVE;

    @Column(name = "created_at", nullable = false, updatable = false)
    @JsonSerialize(using = ToStringSerializer.class)
    private Instant createdAt = Instant.now();

    @OneToMany(mappedBy = "session", cascade = CascadeType.ALL, orphanRemoval = true, fetch = FetchType.EAGER)
    @JsonIgnore
    private List<StoveResource> stoves = new ArrayList<>();

    @OneToMany(mappedBy = "session", cascade = CascadeType.ALL, orphanRemoval = true, fetch = FetchType.EAGER)
    @OrderBy("priorityOrder ASC")
    private List<SessionDish> dishes = new ArrayList<>();

    public CookingSession() {
    }

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }
    public String getUserId() { return userId; }
    public void setUserId(String userId) { this.userId = userId; }
    public int getNumberOfStoves() { return numberOfStoves; }
    public void setNumberOfStoves(int numberOfStoves) { this.numberOfStoves = numberOfStoves; }
    public SessionStatus getStatus() { return status; }
    public void setStatus(SessionStatus status) { this.status = status; }
    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }
    public List<StoveResource> getStoves() { return stoves; }
    public void setStoves(List<StoveResource> stoves) { this.stoves = stoves; }
    public List<SessionDish> getDishes() { return dishes; }
    public void setDishes(List<SessionDish> dishes) { this.dishes = dishes; }
}

package com.example.voice_assistant.entity;

import com.fasterxml.jackson.annotation.JsonIgnore;
import jakarta.persistence.*;

import java.util.UUID;

/** One physical stove/burner belonging to a cooking session - a limited, shared resource. */
@Entity
@Table(name = "stove_resources")
public class StoveResource {

    @Id
    @GeneratedValue
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "session_id", nullable = false)
    @JsonIgnore
    private CookingSession session;

    /** 1-based index shown to the user, e.g. "Stove 1". */
    @Column(name = "stove_index", nullable = false)
    private int stoveIndex;

    @Column(nullable = false)
    private boolean busy = false;

    /** The SessionDishStep currently occupying this stove, if any. */
    @Column(name = "occupied_by_step_id")
    private UUID occupiedByStepId;

    public StoveResource() {
    }

    public StoveResource(CookingSession session, int stoveIndex) {
        this.session = session;
        this.stoveIndex = stoveIndex;
    }

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }
    public CookingSession getSession() { return session; }
    public void setSession(CookingSession session) { this.session = session; }
    public int getStoveIndex() { return stoveIndex; }
    public void setStoveIndex(int stoveIndex) { this.stoveIndex = stoveIndex; }
    public boolean isBusy() { return busy; }
    public void setBusy(boolean busy) { this.busy = busy; }
    public UUID getOccupiedByStepId() { return occupiedByStepId; }
    public void setOccupiedByStepId(UUID occupiedByStepId) { this.occupiedByStepId = occupiedByStepId; }
}

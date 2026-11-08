package com.example.voice_assistant.repository;

import com.example.voice_assistant.entity.SessionDishStep;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

public interface SessionDishStepRepository extends JpaRepository<SessionDishStep, UUID> {

    /**
     * Single joined existence check. Lets a caller reject a step id the app captured before the
     * session moved on, without touching a lazy association outside a transaction.
     */
    boolean existsByIdAndSessionDishSession_Id(UUID id, UUID sessionId);
}

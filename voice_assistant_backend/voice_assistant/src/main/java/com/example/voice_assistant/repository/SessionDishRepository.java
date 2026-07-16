package com.example.voice_assistant.repository;

import com.example.voice_assistant.entity.SessionDish;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface SessionDishRepository extends JpaRepository<SessionDish, UUID> {
    List<SessionDish> findBySession_IdOrderByPriorityOrderAsc(UUID sessionId);
}

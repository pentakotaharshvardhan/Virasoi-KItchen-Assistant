package com.example.voice_assistant.repository;

import com.example.voice_assistant.entity.SessionDishStep;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

public interface SessionDishStepRepository extends JpaRepository<SessionDishStep, UUID> {
}

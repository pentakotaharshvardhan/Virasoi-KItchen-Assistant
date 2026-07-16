package com.example.voice_assistant.repository;

import com.example.voice_assistant.entity.CookingSession;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

public interface CookingSessionRepository extends JpaRepository<CookingSession, UUID> {
}

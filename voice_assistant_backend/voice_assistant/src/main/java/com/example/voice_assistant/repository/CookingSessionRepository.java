package com.example.voice_assistant.repository;

import com.example.voice_assistant.entity.CookingSession;
import com.example.voice_assistant.entity.enums.SessionStatus;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

public interface CookingSessionRepository extends JpaRepository<CookingSession, UUID> {

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select s from CookingSession s where s.id = :id")
    Optional<CookingSession> findByIdForUpdate(@Param("id") UUID id);

    @Query("select s.id from CookingSession s where s.status = :status "
            + "and (s.lastHeartbeatAt is null or s.lastHeartbeatAt < :cutoff)")
    List<UUID> findStaleSessionIds(@Param("status") SessionStatus status, @Param("cutoff") Instant cutoff);
}

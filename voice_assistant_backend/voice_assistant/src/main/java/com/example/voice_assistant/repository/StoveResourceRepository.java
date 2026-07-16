package com.example.voice_assistant.repository;

import com.example.voice_assistant.entity.StoveResource;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface StoveResourceRepository extends JpaRepository<StoveResource, UUID> {
    List<StoveResource> findBySession_IdOrderByStoveIndexAsc(UUID sessionId);
}

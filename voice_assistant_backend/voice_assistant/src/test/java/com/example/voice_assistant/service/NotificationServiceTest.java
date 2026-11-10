package com.example.voice_assistant.service;

import com.example.voice_assistant.dto.response.SessionSnapshotDto;
import com.example.voice_assistant.dto.response.UserTaskDto;
import com.example.voice_assistant.repository.SessionDishStepRepository;
import com.example.voice_assistant.websocket.WebSocketSessionRegistry;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class NotificationServiceTest {

    private final WebSocketSessionRegistry registry = mock(WebSocketSessionRegistry.class);
    private final TextToSpeechService textToSpeechService = mock(TextToSpeechService.class);
    private final InstructionPersonalizationService personalizationService =
            mock(InstructionPersonalizationService.class);
    private final SessionDishStepRepository sessionDishStepRepository = mock(SessionDishStepRepository.class);

    @Test
    void dishCompletionAnnouncementSurvivesInstructionPersonalization() {
        UUID stepId = UUID.randomUUID();
        SessionSnapshotDto snapshot = new SessionSnapshotDto();
        snapshot.sessionId = UUID.randomUUID();
        snapshot.message = "\"Jeera Rice\" is done! Heat the oil in a pan.";
        snapshot.currentUserTask = userTask(stepId, "Heat the oil in a pan.");

        when(sessionDishStepRepository.findById(stepId)).thenReturn(Optional.empty());
        when(registry.nextSeq(anyString())).thenReturn(1L);
        when(registry.get(any())).thenReturn(List.of());
        when(textToSpeechService.synthesizeBase64(anyString())).thenReturn("audio");
        when(personalizationService.personalize(
                anyString(), any(), any(), any(), anyInt(), any())).thenReturn("Now, heat the oil on stove 2.");

        service().pushSnapshot(snapshot.sessionId, snapshot);

        assertEquals("\"Jeera Rice\" is done! Now, heat the oil on stove 2.", snapshot.message);
        verify(personalizationService).personalize(
                eq("Heat the oil in a pan."), isNull(), isNull(), isNull(), eq(1), isNull());
    }

    @Test
    void personalizationFallsBackToTheWholeMessageWhenTheInstructionIsNotASuffix() {
        UUID stepId = UUID.randomUUID();
        SessionSnapshotDto snapshot = new SessionSnapshotDto();
        snapshot.sessionId = UUID.randomUUID();
        snapshot.message = "Waiting for the next available stove or task.";
        snapshot.currentUserTask = userTask(stepId, "Heat the oil in a pan.");

        when(sessionDishStepRepository.findById(stepId)).thenReturn(Optional.empty());
        when(registry.nextSeq(anyString())).thenReturn(1L);
        when(registry.get(any())).thenReturn(List.of());
        when(textToSpeechService.synthesizeBase64(anyString())).thenReturn("audio");
        when(personalizationService.personalize(
                anyString(), any(), any(), any(), anyInt(), any())).thenReturn("Candidate reply");

        service().pushSnapshot(snapshot.sessionId, snapshot);

        assertEquals("Candidate reply", snapshot.message);
        verify(personalizationService).personalize(
                eq("Waiting for the next available stove or task."), isNull(), isNull(), isNull(), eq(1), isNull());
    }

    @Test
    void messageIsUntouchedWhenThereIsNoUserTask() {
        SessionSnapshotDto snapshot = new SessionSnapshotDto();
        snapshot.sessionId = UUID.randomUUID();
        snapshot.message = "\"Paneer Curry\" is done! All dishes are done. Happy meal!";

        when(registry.nextSeq(anyString())).thenReturn(1L);
        when(registry.get(any())).thenReturn(List.of());
        when(textToSpeechService.synthesizeBase64(anyString())).thenReturn("audio");

        service().pushSnapshot(snapshot.sessionId, snapshot);

        assertEquals("\"Paneer Curry\" is done! All dishes are done. Happy meal!", snapshot.message);
        verify(personalizationService, never()).personalize(
                anyString(), any(), any(), any(), anyInt(), any());
    }

    private NotificationService service() {
        return new NotificationService(registry, new ObjectMapper(), textToSpeechService,
                personalizationService, sessionDishStepRepository);
    }

    private UserTaskDto userTask(UUID stepId, String instruction) {
        UserTaskDto task = new UserTaskDto();
        task.stepId = stepId;
        task.instruction = instruction;
        task.status = "IN_PROGRESS";
        return task;
    }
}

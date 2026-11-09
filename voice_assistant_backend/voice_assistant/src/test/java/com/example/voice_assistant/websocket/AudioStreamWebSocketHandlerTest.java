package com.example.voice_assistant.websocket;

import com.example.voice_assistant.dto.ai.VoiceCommandResultDto;
import com.example.voice_assistant.dto.response.SessionSnapshotDto;
import com.example.voice_assistant.dto.response.UserTaskDto;
import com.example.voice_assistant.repository.SessionDishStepRepository;
import com.example.voice_assistant.service.CookingSessionService;
import com.example.voice_assistant.service.InstructionPersonalizationService;
import com.example.voice_assistant.service.NotificationService;
import com.example.voice_assistant.service.RecipeService;
import com.example.voice_assistant.service.SchedulerService;
import com.example.voice_assistant.service.SpeechToTextService;
import com.example.voice_assistant.service.TextToSpeechService;
import com.example.voice_assistant.service.VoiceCommandService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

import java.net.URI;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * One "next" must reach the requesting socket exactly once. The scheduler broadcasts the
 * snapshot to the whole session (NotificationService.pushSnapshot) and the handler used to send
 * its own copy on top of it: two identical frames with two different sequence numbers, so the
 * app's seq check could not drop the second one and the instruction showed up twice.
 */
@ExtendWith(MockitoExtension.class)
class AudioStreamWebSocketHandlerTest {

    private final WebSocketSessionRegistry registry = new WebSocketSessionRegistry();
    private final ObjectMapper objectMapper = new ObjectMapper();
    private final List<TextMessage> sent = new ArrayList<>();
    private final UUID sessionId = UUID.randomUUID();
    private final UUID stepId = UUID.randomUUID();

    @Mock
    private SpeechToTextService speechToTextService;
    @Mock
    private TextToSpeechService textToSpeechService;
    @Mock
    private RecipeService recipeService;
    @Mock
    private CookingSessionService cookingSessionService;
    @Mock
    private SchedulerService schedulerService;
    @Mock
    private VoiceCommandService voiceCommandService;
    @Mock
    private SessionDishStepRepository sessionDishStepRepository;
    @Mock
    private InstructionPersonalizationService instructionPersonalizationService;
    @Mock
    private WebSocketSession socket;

    private AudioStreamWebSocketHandler handler;
    private NotificationService notificationService;

    @BeforeEach
    void setUp() throws Exception {
        notificationService = new NotificationService(registry, objectMapper, textToSpeechService,
                instructionPersonalizationService, sessionDishStepRepository);
        handler = new AudioStreamWebSocketHandler(speechToTextService, textToSpeechService, recipeService,
                cookingSessionService, schedulerService, registry, objectMapper, voiceCommandService,
                sessionDishStepRepository);

        when(socket.isOpen()).thenReturn(true);
        when(socket.getId()).thenReturn("sock-1");
        when(socket.getUri()).thenReturn(URI.create("ws://localhost/ws/audio?sessionId=" + sessionId));
        doAnswer(invocation -> {
            sent.add(invocation.getArgument(0));
            return null;
        }).when(socket).sendMessage(any(TextMessage.class));
        registry.register(sessionId, socket);
    }

    @Test
    void aSnapshotTheSchedulerAlreadyPushedIsNotSentASecondTime() throws Exception {
        when(voiceCommandService.classify(eq("next"), any())).thenReturn(nextCommand());
        when(schedulerService.tickQuietly(sessionId)).thenReturn(snapshot("Finely chop the onion.", stepId));
        when(instructionPersonalizationService.personalize(any(), any(), any(), any(), anyInt(), any()))
                .thenAnswer(invocation -> invocation.getArgument(0));
        when(schedulerService.completeStep(sessionId, stepId)).thenAnswer(invocation -> {
            SessionSnapshotDto pushed = snapshot("Heat the pan and saute the onions.", stepId);
            // exactly what SchedulerService.tick() does inside completeStep() for real
            notificationService.pushSnapshot(sessionId, pushed);
            return pushed;
        });

        handler.handleTextMessage(socket, userText("next"));

        List<JsonNode> frames = snapshotFrames();
        assertEquals(1, frames.size(),
                "the requester already got the broadcast - a second copy is the duplicate reply");
        assertTrue(frames.get(0).path("seq").asLong() > 0, "every frame carries a sequence number");
        // Resolving the implicit step must not dispatch-and-speak on its own.
        verify(schedulerService, never()).tick(sessionId);
        verify(schedulerService).tickQuietly(sessionId);
    }

    @Test
    void aSnapshotTheSchedulerNeverPushedStillReachesTheRequester() throws Exception {
        when(voiceCommandService.classify(eq("next"), any())).thenReturn(nextCommand());
        when(schedulerService.tickQuietly(sessionId)).thenReturn(snapshot("Finely chop the onion.", stepId));
        // e.g. the "session is no longer active" early return: returned before any push
        when(schedulerService.completeStep(sessionId, stepId))
                .thenReturn(snapshot("This cooking session is no longer active.", null));

        handler.handleTextMessage(socket, userText("next"));

        List<JsonNode> frames = snapshotFrames();
        assertEquals(1, frames.size(), "an unpushed snapshot must still be delivered directly");
        assertTrue(frames.get(0).path("seq").asLong() > 0, "every frame carries a sequence number");
    }

    @Test
    void aSecondCommandAfterTheFirstPushStillDeliversOneFrameEach() throws Exception {
        when(voiceCommandService.classify(eq("next"), any())).thenReturn(nextCommand());
        when(schedulerService.tickQuietly(sessionId)).thenReturn(snapshot("Finely chop the onion.", stepId));
        when(instructionPersonalizationService.personalize(any(), any(), any(), any(), anyInt(), any()))
                .thenAnswer(invocation -> invocation.getArgument(0));
        when(schedulerService.completeStep(eq(sessionId), eq(stepId))).thenAnswer(invocation -> {
            SessionSnapshotDto pushed = snapshot("Add the tomatoes.", stepId);
            notificationService.pushSnapshot(sessionId, pushed);
            return pushed;
        });

        handler.handleTextMessage(socket, userText("next"));
        handler.handleTextMessage(socket, userText("next"));

        assertEquals(2, snapshotFrames().size(), "two commands, two snapshots - never three");
    }

    private VoiceCommandResultDto nextCommand() {
        VoiceCommandResultDto dto = new VoiceCommandResultDto();
        dto.command = "NEXT";
        return dto;
    }

    private SessionSnapshotDto snapshot(String message, UUID taskStepId) {
        SessionSnapshotDto snapshot = new SessionSnapshotDto();
        snapshot.sessionId = sessionId;
        snapshot.sessionStatus = "ACTIVE";
        snapshot.message = message;
        if (taskStepId != null) {
            UserTaskDto task = new UserTaskDto();
            task.stepId = taskStepId;
            task.instruction = message;
            snapshot.currentUserTask = task;
        }
        return snapshot;
    }

    private TextMessage userText(String text) throws Exception {
        return new TextMessage(objectMapper.writeValueAsString(Map.of("type", "user_text", "text", text)));
    }

    private List<JsonNode> snapshotFrames() throws Exception {
        List<JsonNode> frames = new ArrayList<>();
        for (TextMessage message : sent) {
            JsonNode node = objectMapper.readTree(message.getPayload());
            if ("session_snapshot".equals(node.path("type").asText())) frames.add(node);
        }
        return frames;
    }
}

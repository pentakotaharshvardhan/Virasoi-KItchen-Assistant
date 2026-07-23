package com.example.voice_assistant.websocket;
import com.example.voice_assistant.dto.ai.VoiceCommandResultDto;
import com.example.voice_assistant.dto.response.SessionSnapshotDto;
import com.example.voice_assistant.service.VoiceCommandService;
import com.example.voice_assistant.dto.response.UserTaskDto;
import com.example.voice_assistant.entity.CookingSession;
import com.example.voice_assistant.entity.Recipe;
import com.example.voice_assistant.service.CookingSessionService;
import com.example.voice_assistant.service.RecipeService;
import com.example.voice_assistant.service.SchedulerService;
import com.example.voice_assistant.service.SpeechToTextService;
import com.example.voice_assistant.service.TextToSpeechService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.web.socket.*;
import org.springframework.web.socket.handler.TextWebSocketHandler;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.net.URI;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * The "continuous listening" WebSocket. Protocol (JSON text control frames interleaved with raw
 * binary audio frames), one utterance at a time:
 *
 *   -> {"action":"start_utterance","field":"dish_name|num_serves|ancestor_transcript|step_command",
 *       "meta":{...optional, e.g. "dishNameHint","createdBy","stepId","seconds"}}
 *   -> <binary audio chunk(s)>  (as many as needed)
 *   -> {"action":"end_utterance"}
 *   <- {"type":"transcript","field":"...","text":"..."}
 *   <- {"type": "...", "data": {...}}   (business result - see handleUtterance)
 *
 * Connect with query params: ws://host/ws/audio?token=<jwt>&sessionId=<uuid optional>
 * `sessionId` is required for "num_serves" and "step_command" fields (it identifies the
 * CookingSession); it's optional for "ancestor_transcript" and a first "dish_name" lookup.
 *
 * Every "prompt" message (and every session_snapshot, via NotificationService) also carries an
 * "audioBase64"/"messageAudioBase64" field with synthesized speech (Google Cloud TTS) so the
 * Flutter app can just play audio instead of doing its own on-device TTS.
 */
public class AudioStreamWebSocketHandler extends TextWebSocketHandler {

    private static final Pattern DIGITS = Pattern.compile("(\\d+)");

    private final SpeechToTextService speechToTextService;
    private final TextToSpeechService textToSpeechService;
    private final RecipeService recipeService;
    private final CookingSessionService cookingSessionService;
    private final SchedulerService schedulerService;
    private final WebSocketSessionRegistry registry;
    private final ObjectMapper objectMapper;
    private final VoiceCommandService voiceCommandService; // ADD

    // per-socket scratch state
    private final Map<String, ByteArrayOutputStream> buffers = new ConcurrentHashMap<>();
    private final Map<String, String> pendingField = new ConcurrentHashMap<>();
    private final Map<String, Map<String, Object>> pendingMeta = new ConcurrentHashMap<>();
    private final Map<String, String> pendingDishName = new ConcurrentHashMap<>();
    private final Map<String, String> lastSpokenMessage = new ConcurrentHashMap<>(); // ADD - for REPEAT

    public AudioStreamWebSocketHandler(SpeechToTextService speechToTextService, TextToSpeechService textToSpeechService,
                                       RecipeService recipeService, CookingSessionService cookingSessionService,
                                       SchedulerService schedulerService, WebSocketSessionRegistry registry,
                                       ObjectMapper objectMapper, VoiceCommandService voiceCommandService) { // ADD param
        this.speechToTextService = speechToTextService;
        this.textToSpeechService = textToSpeechService;
        this.recipeService = recipeService;
        this.cookingSessionService = cookingSessionService;
        this.schedulerService = schedulerService;
        this.registry = registry;
        this.objectMapper = objectMapper;
        this.voiceCommandService = voiceCommandService; // ADD
    }

    @Override
    public void afterConnectionEstablished(WebSocketSession session) throws Exception {
        buffers.put(session.getId(), new ByteArrayOutputStream());
        UUID cookingSessionId = extractSessionId(session);
        if (cookingSessionId != null) {
            registry.register(cookingSessionId, session);
        }
        send(session, "connected", Map.of("message", "Listening..."));
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
        buffers.remove(session.getId());
        pendingField.remove(session.getId());
        pendingMeta.remove(session.getId());
        pendingDishName.remove(session.getId());
        lastSpokenMessage.remove(session.getId()); // ADD
        UUID cookingSessionId = extractSessionId(session);
        if (cookingSessionId != null) {
            registry.unregister(cookingSessionId, session);
        }
    }

    @Override
    protected void handleTextMessage(WebSocketSession session, TextMessage message) throws Exception {
        JsonNode node = objectMapper.readTree(message.getPayload());
        String action = node.path("action").asText("");

        switch (action) {
            case "start_utterance" -> {
                buffers.get(session.getId()).reset();
                pendingField.put(session.getId(), node.path("field").asText(""));
                Map<String, Object> meta = node.hasNonNull("meta")
                        ? objectMapper.convertValue(node.path("meta"), Map.class)
                        : Map.of();
                pendingMeta.put(session.getId(), meta == null ? Map.of() : meta);
            }
            case "end_utterance" -> handleUtterance(session);
            case "ping" -> send(session, "pong", Map.of());
            default -> send(session, "error", Map.of("message", "Unknown action: " + action));
        }
    }

    @Override
    protected void handleBinaryMessage(WebSocketSession session, BinaryMessage message) {
        ByteArrayOutputStream buffer = buffers.get(session.getId());
        if (buffer != null) {
            try {
                buffer.write(message.getPayload().array());
            } catch (IOException e) {
                throw new RuntimeException(e);
            }
        }
    }

    private void handleUtterance(WebSocketSession session) throws Exception {
        String field = pendingField.getOrDefault(session.getId(), "");
        Map<String, Object> meta = pendingMeta.getOrDefault(session.getId(), Map.of());
        byte[] audio = buffers.get(session.getId()).toByteArray();

        String transcript;
        try {
            transcript = speechToTextService.transcribe(audio, "utterance.wav");
        } catch (Exception e) {
            send(session, "error", Map.of("message", "Transcription failed: " + e.getMessage()));
            return;
        }
        send(session, "transcript", Map.of("field", field, "text", transcript));

        try {
            switch (field) {
                case "ancestor_transcript" -> {
                    String dishNameHint = (String) meta.getOrDefault("dishNameHint", "");
                    String createdBy = (String) meta.getOrDefault("createdBy", "");
                    Recipe saved = recipeService.uploadAncestorRecipe(transcript, dishNameHint, createdBy);
                    send(session, "recipe_saved", saved);
                }
                case "dish_name" -> {
                    Recipe recipe = recipeService.findOrGenerate(transcript);
                    pendingDishName.put(session.getId(), recipe.getDishName());
                    send(session, "recipe_found", recipe);
                    sendPrompt(session, "num_serves", "Got it, " + recipe.getDishName() + ". How many people are you serving?");
                }
                case "num_serves" -> {
                    UUID sessionId = extractSessionId(session);
                    String dishName = pendingDishName.get(session.getId());
                    if (sessionId == null || dishName == null) {
                        send(session, "error", Map.of("message",
                                "No active cooking session / pending dish. Start a session and say the dish name first."));
                        break;
                    }
                    int serves = extractFirstNumber(transcript, 1);
                    CookingSession cs = cookingSessionService.getById(sessionId);
                    cookingSessionService.addDish(cs, dishName, serves);
                    pendingDishName.remove(session.getId());
                    SessionSnapshotDto snapshot = schedulerService.tick(sessionId); // NotificationService already attaches speech
                    send(session, "session_snapshot", snapshot);
                }
                case "step_command" -> {
                    UUID sessionId = extractSessionId(session);
                    if (sessionId == null) {
                        send(session, "error", Map.of("message", "sessionId query param is required for step_command"));
                        break;
                    }
                    handleStepCommand(session, sessionId, transcript, meta);
                }
                default -> send(session, "error", Map.of("message", "Unknown field: " + field));
            }
        } catch (Exception e) {
            send(session, "error", Map.of("message", e.getMessage() == null ? e.toString() : e.getMessage()));
        }
    }

    private void handleStepCommand(WebSocketSession session, UUID sessionId, String transcript, Map<String, Object> meta) throws Exception {
        VoiceCommandResultDto parsed = voiceCommandService.classify(transcript);
        VoiceCommandService.Command command;
        try {
            command = VoiceCommandService.Command.valueOf(parsed.command);
        } catch (Exception e) {
            command = VoiceCommandService.Command.UNKNOWN;
        }

        // HELP and REMOVE don't touch scheduler state - handle immediately.
        if (command == VoiceCommandService.Command.HELP) {
            String answer = (parsed.helpResponse != null && !parsed.helpResponse.isBlank())
                    ? parsed.helpResponse
                    : "I'm here to help - what would you like to know about the app?";
            sendPrompt(session, "help", answer);
            return;
        }
        if (command == VoiceCommandService.Command.REMOVE) {
            // No server-tracked pantry list exists - this is a client-side concern. Echo back what
            // was understood so the Flutter Ingredient screen can remove it from its local list.
            send(session, "remove_ingredient", Map.of("ingredientName", parsed.ingredientName == null ? "" : parsed.ingredientName));
            return;
        }

        // Resolve which step this applies to: an explicit stove number or dish name (needed when
        // more than one might be waiting on the user at once) takes priority over the scheduler's
        // single implicit "current task" guess.
        UUID stepId = null;
        if (parsed.stoveIndex != null) {
            stepId = schedulerService.findStepIdForStove(sessionId, parsed.stoveIndex).orElse(null);
        }
        if (stepId == null && parsed.dishName != null && !parsed.dishName.isBlank()) {
            stepId = schedulerService.findActiveStepIdForDish(sessionId, parsed.dishName).orElse(null);
        }
        if (stepId == null) {
            stepId = meta.get("stepId") != null ? UUID.fromString(meta.get("stepId").toString()) : currentUserTaskStepId(sessionId);
        }
        if (stepId == null) {
            send(session, "error", Map.of("message", "I couldn't tell which step you mean - try naming the stove number or dish."));
            return;
        }

        SessionSnapshotDto snapshot;
        switch (command) {
            case NEXT -> snapshot = schedulerService.completeStep(sessionId, stepId);
            case WAIT -> snapshot = schedulerService.waitOnStep(sessionId, stepId);
            case TIMER_YES -> {
                int seconds = parsed.timerSeconds != null ? parsed.timerSeconds : extractFirstNumber(transcript, 180);
                snapshot = schedulerService.startOptionalTimer(sessionId, stepId, seconds);
            }
            case TIMER_NO -> snapshot = schedulerService.tick(sessionId);
            case REPEAT -> {
                String last = lastSpokenMessage.getOrDefault(session.getId(), "Nothing to repeat yet.");
                sendPrompt(session, "step_command", last);
                return;
            }
            case STOP -> {
                send(session, "info", Map.of("message", "Okay, pausing here. Say \"next\" whenever you're ready to continue."));
                return;
            }
            default -> {
                send(session, "error", Map.of("message", "Didn't understand step command: \"" + transcript + "\""));
                return;
            }
        }

        lastSpokenMessage.put(session.getId(), snapshot.message);
        send(session, "session_snapshot", snapshot);
    }

    private UUID currentUserTaskStepId(UUID sessionId) {
        SessionSnapshotDto snapshot = schedulerService.tick(sessionId);
        UserTaskDto task = snapshot.currentUserTask;
        return task == null ? null : task.stepId;
    }

    private boolean containsAny(String haystack, String... needles) {
        for (String n : needles) {
            if (haystack.contains(n)) return true;
        }
        return false;
    }

    private int extractFirstNumber(String text, int fallback) {
        if (text == null) return fallback;
        Matcher m = DIGITS.matcher(text);
        if (m.find()) {
            try {
                return Integer.parseInt(m.group(1));
            } catch (NumberFormatException ignored) {
            }
        }
        return fallback;
    }

    private UUID extractSessionId(WebSocketSession session) {
        URI uri = session.getUri();
        if (uri == null || uri.getQuery() == null) return null;
        for (String param : uri.getQuery().split("&")) {
            String[] kv = param.split("=", 2);
            if (kv.length == 2 && kv[0].equals("sessionId")) {
                try {
                    return UUID.fromString(kv[1]);
                } catch (IllegalArgumentException ignored) {
                    return null;
                }
            }
        }
        return null;
    }

    /** Sends a spoken prompt: text + Base64 TTS audio in one message, so the app can just play it. */
    private void sendPrompt(WebSocketSession session, String field, String message) throws Exception {
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("field", field);
        data.put("message", message);
        String audioBase64 = textToSpeechService.synthesizeBase64(message);
        if (audioBase64 != null) {
            data.put("audioBase64", audioBase64);
            data.put("audioEncoding", "MP3");
        }
        send(session, "prompt", data);
    }

    private void send(WebSocketSession session, String type, Object data) throws Exception {
        String payload = objectMapper.writeValueAsString(Map.of("type", type, "data", data));
        if (session.isOpen()) {
            synchronized (session) {
                session.sendMessage(new TextMessage(payload));
            }
        }
    }
}

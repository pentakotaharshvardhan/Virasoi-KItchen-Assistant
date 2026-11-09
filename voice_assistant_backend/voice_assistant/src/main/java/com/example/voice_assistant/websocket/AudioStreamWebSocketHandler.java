package com.example.voice_assistant.websocket;
import com.example.voice_assistant.dto.ai.VoiceCommandResultDto;
import com.example.voice_assistant.dto.response.SessionSnapshotDto;
import com.example.voice_assistant.service.VoiceCommandService;
import com.example.voice_assistant.dto.response.UserTaskDto;
import com.example.voice_assistant.entity.CookingSession;
import com.example.voice_assistant.entity.Recipe;
import com.example.voice_assistant.repository.SessionDishStepRepository;
import com.example.voice_assistant.service.CookingSessionService;
import com.example.voice_assistant.service.RecipeService;
import com.example.voice_assistant.service.SchedulerService;
import com.example.voice_assistant.service.SpeechToTextService;
import com.example.voice_assistant.service.TextToSpeechService;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.web.socket.*;
import org.springframework.web.socket.handler.TextWebSocketHandler;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.net.URI;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
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
    private final SessionDishStepRepository sessionDishStepRepository;

    // per-socket scratch state
    private final Map<String, ByteArrayOutputStream> buffers = new ConcurrentHashMap<>();
    private final Map<String, String> pendingField = new ConcurrentHashMap<>();
    private final Map<String, Map<String, Object>> pendingMeta = new ConcurrentHashMap<>();
    private final Map<String, String> pendingDishName = new ConcurrentHashMap<>();
    private final Map<String, String> lastSpokenMessage = new ConcurrentHashMap<>(); // ADD - for REPEAT

    public AudioStreamWebSocketHandler(SpeechToTextService speechToTextService, TextToSpeechService textToSpeechService,
                                       RecipeService recipeService, CookingSessionService cookingSessionService,
                                       SchedulerService schedulerService, WebSocketSessionRegistry registry,
                                       ObjectMapper objectMapper, VoiceCommandService voiceCommandService,
                                       SessionDishStepRepository sessionDishStepRepository) { // ADD param
        this.speechToTextService = speechToTextService;
        this.textToSpeechService = textToSpeechService;
        this.recipeService = recipeService;
        this.cookingSessionService = cookingSessionService;
        this.schedulerService = schedulerService;
        this.registry = registry;
        this.objectMapper = objectMapper;
        this.voiceCommandService = voiceCommandService; // ADD
        this.sessionDishStepRepository = sessionDishStepRepository;
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
        String type = node.path("type").asText("");

        // The Flutter app does on-device speech-to-text and sends the finished text as
        // {"type":"user_text","text":...}. Classify + route it exactly like a spoken utterance.
        if (action.isEmpty() && "user_text".equals(type)) {
            String text = node.path("text").asText(node.path("transcript").asText(""));
            try {
                handleUserText(session, text, readIngredientCandidates(node.path("availableIngredientNames")));
            } catch (Exception e) {
                sendFriendlyError(session, e);
            }
            return;
        }

        // Flutter classifies through POST /api/ai/command and forwards the typed result here,
        // avoiding a duplicate Gemini request before applying a scheduler action.
        if (action.isEmpty() && "command_result".equals(type)) {
            if (!node.path("result").isObject()) {
                send(session, "error", Map.of("message", "The command result must be a JSON object."));
                return;
            }
            VoiceCommandResultDto parsed;
            try {
                parsed = objectMapper.treeToValue(node.path("result"), VoiceCommandResultDto.class);
            } catch (JsonProcessingException e) {
                send(session, "error", Map.of("message", "The command result contains invalid parameters."));
                return;
            }
            try {
                handleClassifiedUserText(session, node.path("text").asText(""), parsed);
            } catch (Exception e) {
                sendFriendlyError(session, e);
            }
            return;
        }

        if (action.isEmpty() && "heartbeat".equals(type)) {
            UUID sessionId = extractSessionId(session);
            if (sessionId != null) schedulerService.heartbeat(sessionId);
            send(session, "heartbeat_ack", Map.of());
            return;
        }

        // A client (re)connecting to an in-progress session asks for the current state so it can
        // speak the active instruction instead of sitting on a stale orb. Marked as a replay so
        // repeating the instruction the user just heard doesn't get spoken twice.
        if (action.isEmpty() && "status".equals(type)) {
            UUID sessionId = extractSessionId(session);
            if (sessionId != null) {
                send(session, "session_snapshot", schedulerService.status(sessionId), true);
            }
            return;
        }

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
            case "ping" -> {
                UUID sessionId = extractSessionId(session);
                if (sessionId != null) schedulerService.heartbeat(sessionId);
                send(session, "pong", Map.of());
            }
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
                    Recipe saved = recipeService.uploadAncestorRecipe(
                            transcript, dishNameHint, createdBy, currentUserId(session));
                    send(session, "recipe_saved", saved);
                }
                case "dish_name" -> {
                    Recipe recipe = recipeService.findOrGenerate(transcript, currentUserId(session));
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
                    sendSnapshot(session, sessionId, snapshot);
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

    /**
     * Handles free-text commands (already transcribed on the device). Shared by the typed
     * {"type":"user_text"} protocol and the legacy {"action":"step_command"} audio protocol.
     */
    private void handleUserText(
            WebSocketSession session, String transcript, List<String> ingredientCandidates) throws Exception {
        if (transcript == null || transcript.isBlank()) {
            sendPrompt(session, "step_command", "I didn't catch that. Could you say it again?");
            return;
        }

        VoiceCommandResultDto parsed = voiceCommandService.classify(transcript, ingredientCandidates);
        handleClassifiedUserText(session, transcript, parsed);
    }

    private void handleClassifiedUserText(
            WebSocketSession session, String transcript, VoiceCommandResultDto parsed) throws Exception {
        VoiceCommandService.Command command;
        try {
            command = VoiceCommandService.Command.valueOf(parsed.command);
        } catch (Exception e) {
            command = VoiceCommandService.Command.UNKNOWN;
        }
        UUID sessionId = extractSessionId(session);

        if (command == VoiceCommandService.Command.HELP) {
            String answer = (parsed.helpResponse != null && !parsed.helpResponse.isBlank())
                    ? parsed.helpResponse
                    : "I'm here to help - what would you like to know about the app?";
            sendPrompt(session, "help", answer);
            return;
        }

        if (command == VoiceCommandService.Command.REMOVE) {
            handleRemove(session, sessionId, parsed);
            return;
        }

        if (command == VoiceCommandService.Command.REMAINING_ITEMS) {
            // The checklist itself lives on the Flutter Ingredient screen - ask it to read out
            // whatever is still pending.
            handleRemainingItems(session);
            return;
        }

        if (command == VoiceCommandService.Command.UNKNOWN) {
            sendPrompt(session, "step_command",
                    "I'm sorry, I didn't understand that. You can say next, wait, repeat, stop, or \"I am free\".");
            return;
        }

        if (sessionId == null) {
            send(session, "error", Map.of("message", "sessionId query param is required for cooking commands"));
            return;
        }
        handleParsedStepCommand(session, sessionId, transcript, Map.of(), parsed);
    }

    /** Broadcasts every understood ingredient (single OR multiple) to the Ingredient screen's
     *  socket and acknowledges on the speaker's socket. */
    private void handleRemove(WebSocketSession session, UUID sessionId, VoiceCommandResultDto parsed) throws Exception {
        List<String> names = new ArrayList<>();
        if (parsed.ingredientNames != null) {
            for (String n : parsed.ingredientNames) {
                if (n != null && !n.isBlank()) names.add(n.trim());
            }
        }
        if (names.isEmpty() && parsed.ingredientName != null && !parsed.ingredientName.isBlank()) {
            names.add(parsed.ingredientName.trim());
        }

        String message = names.isEmpty()
                ? "Which ingredient should I remove?"
                : "Okay, removing " + joinNames(names) + " from your list.";

        broadcast(sessionId, "remove_ingredient", Map.of(
                "ingredientNames", names,
                "ingredientName", names.isEmpty() ? "" : names.get(0),
                "message", message), null);
        sendPrompt(session, "remove_ingredient", message);
    }

    private void handleRemainingItems(WebSocketSession session) throws Exception {
        send(session, "remaining_items_request", Map.of("message", "Which items are still on the list?"));
    }

    private static String joinNames(List<String> names) {
        if (names.size() == 1) return names.get(0);
        if (names.size() == 2) return names.get(0) + " and " + names.get(1);
        return String.join(", ", names.subList(0, names.size() - 1)) + " and " + names.get(names.size() - 1);
    }

    private void handleStepCommand(WebSocketSession session, UUID sessionId, String transcript, Map<String, Object> meta) throws Exception {
        VoiceCommandResultDto parsed = voiceCommandService.classify(transcript);
        handleParsedStepCommand(session, sessionId, transcript, meta, parsed);
    }

    private void handleParsedStepCommand(WebSocketSession session, UUID sessionId, String transcript,
                                         Map<String, Object> meta, VoiceCommandResultDto parsed) throws Exception {
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
            handleRemove(session, sessionId, parsed);
            return;
        }
        if (command == VoiceCommandService.Command.REMAINING_ITEMS) {
            handleRemainingItems(session);
            return;
        }
        if (command == VoiceCommandService.Command.FREE_USER) {
            SessionSnapshotDto snapshot = schedulerService.releaseUser(sessionId);
            lastSpokenMessage.put(session.getId(), snapshot.message);
            sendSnapshot(session, sessionId, snapshot);
            return;
        }
        if (command == VoiceCommandService.Command.NEXT
                && ((parsed.stoveIndices != null && !parsed.stoveIndices.isEmpty())
                || parsed.stoveIndex != null)) {
            List<Integer> stoveIndices = parsed.stoveIndices != null && !parsed.stoveIndices.isEmpty()
                    ? parsed.stoveIndices
                    : List.of(parsed.stoveIndex);
            SessionSnapshotDto snapshot = schedulerService.completeStoveSteps(sessionId, stoveIndices);
            lastSpokenMessage.put(session.getId(), snapshot.message);
            sendSnapshot(session, sessionId, snapshot);
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
            stepId = resolveClientStepId(sessionId, meta.get("stepId"));
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
        sendSnapshot(session, sessionId, snapshot);
    }

    /**
     * The scheduler methods (tick/completeStep/waitOnStep/...) already broadcast the snapshot to
     * every socket of the session through NotificationService.pushSnapshot(). Sending it again
     * from here gave the requester two identical frames with two different sequence numbers, so
     * the app's seq check could not drop the second one and the instruction appeared twice.
     */
    private void sendSnapshot(WebSocketSession session, UUID sessionId, SessionSnapshotDto snapshot) throws Exception {
        boolean alreadyReceived = snapshot.alreadyPushed
                && sessionId != null
                && registry.get(sessionId).contains(session);
        if (alreadyReceived) return;
        send(session, "session_snapshot", snapshot);
    }

    /**
     * A command that cannot be applied must never escape the handler: Spring closes the websocket
     * on an uncaught exception, which the app shows as "connection lost" mid-cook. Report it as a
     * normal error frame instead so the assistant keeps listening.
     */
    private void sendFriendlyError(WebSocketSession session, Exception e) {
        String raw = e.getMessage() == null ? "" : e.getMessage();
        String message = raw.contains("not currently active")
                ? "That step isn't active right now - say \"repeat\" to hear where you are."
                : "I couldn't apply that just now. Please say it again.";
        try {
            send(session, "error", Map.of("message", message));
        } catch (Exception ignored) {
            // Socket already gone - nothing left to notify.
        }
    }

    /**
     * A client-supplied step id is trusted only when the row actually belongs to this session
     * (it may be stale from a previous run of the screen). The live current task is then used as
     * the fallback. Server-derived ids are never re-checked: an extra lookup used to call
     * {@code tick()} twice, and each tick spoke its own (AI-rewritten) version of the instruction.
     */
    private UUID resolveClientStepId(UUID sessionId, Object rawStepId) {
        UUID candidate = parseStepId(rawStepId);
        if (candidate != null && sessionId != null
                && sessionDishStepRepository.existsByIdAndSessionDishSession_Id(candidate, sessionId)) {
            return candidate;
        }
        return currentUserTaskStepId(sessionId);
    }

    private UUID currentUserTaskStepId(UUID sessionId) {
        // Quiet on purpose: resolving the step must not push/speak a snapshot of its own. The
        // command that follows pushes exactly one frame.
        SessionSnapshotDto snapshot = schedulerService.tickQuietly(sessionId);
        UserTaskDto task = snapshot.currentUserTask;
        return task == null ? null : task.stepId;
    }

    /** meta.stepId arrives as free-form text; a malformed id must not blow up the socket. */
    private UUID parseStepId(Object raw) {
        if (raw == null) return null;
        try {
            return UUID.fromString(raw.toString());
        } catch (IllegalArgumentException e) {
            return null;
        }
    }

    private boolean containsAny(String haystack, String... needles) {
        for (String n : needles) {
            if (haystack.contains(n)) return true;
        }
        return false;
    }

    private List<String> readIngredientCandidates(JsonNode node) {
        if (!node.isArray()) return List.of();
        List<String> candidates = new ArrayList<>();
        node.forEach(value -> {
            if (candidates.size() < 100 && value.isTextual()
                    && !value.asText().isBlank() && value.asText().length() <= 120) {
                candidates.add(value.asText().trim());
            }
        });
        return candidates;
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

    /** App user id stashed by JwtHandshakeInterceptor on the WebSocket handshake. */
    private String currentUserId(WebSocketSession session) {
        Object userId = session.getAttributes().get("userId");
        return userId == null ? null : userId.toString();
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

    /** Sends a message to every socket registered for this session. One sequence number per event. */
    private void broadcast(UUID sessionId, String type, Object data, WebSocketSession exclude) throws Exception {
        if (sessionId == null) return;
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("type", type);
        payload.put("data", data);
        payload.put("seq", registry.nextSeq(WebSocketSessionRegistry.sessionChannel(sessionId)));
        String json = objectMapper.writeValueAsString(payload);
        for (WebSocketSession ws : registry.get(sessionId)) {
            if (ws == exclude || !ws.isOpen()) continue;
            synchronized (ws) {
                ws.sendMessage(new TextMessage(json));
            }
        }
    }

    private void send(WebSocketSession session, String type, Object data) throws Exception {
        send(session, type, data, false);
    }

    /**
     * Sends a frame stamped with a per-session sequence number. {@code replay} marks a
     * response that merely repeats current state (a client re-asked for the snapshot), which
     * the app shows without re-speaking if it already said the same thing.
     */
    private void send(WebSocketSession session, String type, Object data, boolean replay) throws Exception {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("type", type);
        payload.put("data", data);
        payload.put("seq", nextSeq(session));
        if (replay) payload.put("replay", true);
        if (session.isOpen()) {
            String json = objectMapper.writeValueAsString(payload);
            synchronized (session) {
                session.sendMessage(new TextMessage(json));
            }
        }
    }

    /** Frames for a cooking session share its counter; frames outside one (help mode) use the socket. */
    private long nextSeq(WebSocketSession session) {
        UUID sessionId = extractSessionId(session);
        String channel = sessionId != null
                ? WebSocketSessionRegistry.sessionChannel(sessionId)
                : "socket:" + session.getId();
        return registry.nextSeq(channel);
    }
}

package com.example.voice_assistant.controller;

import com.example.voice_assistant.dto.request.AddDishRequest;
import com.example.voice_assistant.dto.request.StartSessionRequest;
import com.example.voice_assistant.dto.response.SessionSnapshotDto;
import com.example.voice_assistant.dto.response.StoveStatusDto;
import com.example.voice_assistant.entity.CookingSession;
import com.example.voice_assistant.entity.SessionDish;
import com.example.voice_assistant.service.CookingSessionService;
import com.example.voice_assistant.service.SchedulerService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Min;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.UUID;

/**
 * Everything for running an actual cooking session: starting it (how many stoves), adding dishes
 * (how many serves), and driving the step-by-step flow (done / wait / start a timer). The voice
 * WebSocket at /ws/audio calls into the exact same SchedulerService/CookingSessionService methods -
 * these REST endpoints are the typed equivalent, handy for the Flutter app's non-voice UI and testing.
 */
@RestController
@RequestMapping("/api/sessions")
public class CookingSessionController {

    private final CookingSessionService cookingSessionService;
    private final SchedulerService schedulerService;

    public CookingSessionController(CookingSessionService cookingSessionService, SchedulerService schedulerService) {
        this.cookingSessionService = cookingSessionService;
        this.schedulerService = schedulerService;
    }

    /**
     * Step 1: user says how many stoves they have. Creates the session and its stove resource pool.
     * The session is tied to whoever the "Authorization: Bearer <token>" JWT belongs to - any
     * `userId` in the request body is ignored, so one user can never spoof another's session.
     */
    @PostMapping("/start")
    public CookingSession start(@Valid @RequestBody StartSessionRequest request, Authentication authentication) {
        return cookingSessionService.startSession(authentication.getName(), request.getNumberOfStoves());
    }

    @GetMapping("/{sessionId}/stoves/{stoveIndex}")
    public StoveStatusDto getStove(@PathVariable UUID sessionId, @PathVariable int stoveIndex) {
        return schedulerService.getStoveStatus(sessionId, stoveIndex);
    }

    @GetMapping("/{sessionId}")
    public CookingSession get(@PathVariable UUID sessionId) {
        return cookingSessionService.getById(sessionId);
    }

    /** Current live picture of the session: stove states, the user's current task, and dish progress. */
    @GetMapping("/{sessionId}/status")
    public SessionSnapshotDto status(@PathVariable UUID sessionId) {
        return schedulerService.tick(sessionId);
    }

    /**
     * Step 2: user names a dish + how many people it's for. Finds/generates + scales the recipe,
     * queues it in the session, and immediately re-runs the scheduler so it's dispatched if a
     * stove/user resource happens to be free right away.
     */
    @PostMapping("/{sessionId}/dishes")
    public SessionSnapshotDto addDish(@PathVariable UUID sessionId, @Valid @RequestBody AddDishRequest request) {
        CookingSession session = cookingSessionService.getById(sessionId);
        SessionDish dish = cookingSessionService.addDish(session, request.getDishName(), request.getServesRequested());
        SessionSnapshotDto snapshot = schedulerService.tick(sessionId);
        snapshot.message = "Added \"" + dish.getDishName() + "\" for " + dish.getServesRequested() + " serve(s). " + snapshot.message;
        return snapshot;
    }

    /** User confirms a step is done ("next" / "finished") - frees its resource and dispatches whatever's next. */
    @PostMapping("/{sessionId}/steps/{stepId}/complete")
    public SessionSnapshotDto completeStep(@PathVariable UUID sessionId, @PathVariable UUID stepId) {
        return schedulerService.completeStep(sessionId, stepId);
    }

    /** User says "wait" after a timer finishes - holds the resource, doesn't advance yet. */
    @PostMapping("/{sessionId}/steps/{stepId}/wait")
    public SessionSnapshotDto waitOnStep(@PathVariable UUID sessionId, @PathVariable UUID stepId) {
        return schedulerService.waitOnStep(sessionId, stepId);
    }

    /** Opt-in timer for a step the recipe didn't already time (e.g. "want a timer while you chop?" -> yes). */
    @PostMapping("/{sessionId}/steps/{stepId}/timer/start")
    public SessionSnapshotDto startTimer(@PathVariable UUID sessionId, @PathVariable UUID stepId,
                                          @RequestParam @Min(1) int seconds) {
        return schedulerService.startOptionalTimer(sessionId, stepId, seconds);
    }

    /** Manually force a re-evaluation of the scheduler (rarely needed - every action already re-ticks). */
    @PostMapping("/{sessionId}/tick")
    public SessionSnapshotDto tick(@PathVariable UUID sessionId) {
        return schedulerService.tick(sessionId);
    }
}

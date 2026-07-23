package com.example.voice_assistant.service;

import com.example.voice_assistant.dto.response.*;
import com.example.voice_assistant.entity.*;
import com.example.voice_assistant.entity.enums.DishStatus;
import com.example.voice_assistant.entity.enums.SessionStatus;
import com.example.voice_assistant.entity.enums.StepStatus;
import com.example.voice_assistant.entity.enums.StepType;
import com.example.voice_assistant.exception.ResourceNotFoundException;
import com.example.voice_assistant.repository.CookingSessionRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * THE BRAIN of the assistant.
 *
 * Models the kitchen as a tiny OS-style resource scheduler with two resource pools:
 *   - N stove resources (StoveResource rows, N = session.numberOfStoves)
 *   - 1 user resource (there's only one cook)
 *
 * Every dish is a "process" walking through an ordered list of "instructions" (SessionDishStep).
 * Each instruction declares what resource it needs (StepType: STOVE / USER_ACTION / PASSIVE).
 * tick() is the scheduler's dispatch loop: for every active dish, if its current step's required
 * resource is free, the step is dispatched (assigned) - first-come-first-served across dishes,
 * ordered by the order they were added to the session (priorityOrder), mirroring FCFS scheduling.
 * PASSIVE steps need no resource and start immediately (background work, e.g. "let it rest").
 *
 * This is exactly how the app avoids ever double-booking a stove, and how it fills otherwise-idle
 * user time on dish B with a chopping/whisking task while dish A simmers unattended on the stove.
 */
@Service
public class SchedulerService {

    private final CookingSessionRepository sessionRepository;
    private final TimerService timerService;
    private final NotificationService notificationService;
    private final CookingSessionService cookingSessionService;


    public SchedulerService(CookingSessionRepository sessionRepository, TimerService timerService,
                             NotificationService notificationService, CookingSessionService cookingSessionService) {
        this.sessionRepository = sessionRepository;
        this.timerService = timerService;
        this.notificationService = notificationService;
        this.cookingSessionService = cookingSessionService;
    }

    /** Re-evaluates the whole session, dispatching any steps whose required resource just became free. */
    @Transactional
    public SessionSnapshotDto tick(UUID sessionId) {
        CookingSession session = loadSession(sessionId);
        if (session.getStatus() != SessionStatus.ACTIVE) {
            return buildSnapshot(session, "This session has already finished.");
        }

        // Loop so that auto-completing PASSIVE (no-timer) steps immediately free up the next
        // step in that dish within the same tick, instead of waiting for an external event.
        boolean changed = true;
        int guard = 0;
        while (changed && guard++ < 100) {
            changed = dispatchOnce(session);
        }

        sessionRepository.save(session);
        cookingSessionService.markSessionCompletedIfAllDishesDone(session);

        SessionSnapshotDto snapshot = buildSnapshot(session, computeMessage(session));
        notificationService.pushSnapshot(sessionId, snapshot);
        return snapshot;
    }

    /** Resolves which step is currently occupying a given stove, if any. Lets the user say
     *  "stove 1 is free" instead of relying on the single implicit currentUserTask when multiple
     *  stoves might have simultaneous waiting timers. */
    public Optional<UUID> findStepIdForStove(UUID sessionId, int stoveIndex) {
        CookingSession session = loadSession(sessionId);
        return session.getStoves().stream()
                .filter(s -> s.getStoveIndex() == stoveIndex)
                .findFirst()
                .map(StoveResource::getOccupiedByStepId);
    }

    /** Resolves the currently-active step for a named dish (fuzzy, case-insensitive contains match),
     *  so the user can say "the paneer is done" instead of only ever addressing one implicit task. */
    public Optional<UUID> findActiveStepIdForDish(UUID sessionId, String dishNameQuery) {
        if (dishNameQuery == null || dishNameQuery.isBlank()) return Optional.empty();
        CookingSession session = loadSession(sessionId);
        String normalized = dishNameQuery.trim().toLowerCase();
        return session.getDishes().stream()
                .filter(d -> d.getDishName() != null && d.getDishName().toLowerCase().contains(normalized))
                .flatMap(d -> d.getSteps().stream())
                .filter(s -> s.getStatus() == StepStatus.IN_PROGRESS
                        || s.getStatus() == StepStatus.TIMER_RUNNING
                        || s.getStatus() == StepStatus.TIMER_COMPLETED_AWAITING_USER)
                .map(SessionDishStep::getId)
                .findFirst();
    }

    /** One dispatch pass across all active dishes. Returns true if anything changed (so tick() can loop). */
    private boolean dispatchOnce(CookingSession session) {
        boolean userBusy = isUserBusy(session);
        boolean changedAnything = false;

        List<SessionDish> orderedDishes = session.getDishes().stream()
                .filter(d -> d.getStatus() != DishStatus.COMPLETED)
                .sorted(Comparator.comparingInt(SessionDish::getPriorityOrder))
                .toList();

        for (SessionDish dish : orderedDishes) {
            if (dish.getCurrentStepIndex() >= dish.getSteps().size()) {
                dish.setStatus(DishStatus.COMPLETED);
                changedAnything = true;
                continue;
            }

            SessionDishStep step = dish.getSteps().get(dish.getCurrentStepIndex());
            if (step.getStatus() != StepStatus.PENDING) {
                continue; // already dispatched/running/awaiting user - nothing to do this pass
            }

            if (dish.getStatus() == DishStatus.PENDING) {
                dish.setStatus(DishStatus.IN_PROGRESS);
            }

            switch (step.getStepType()) {
                case PASSIVE -> {
                    beginStep(session, step, null);
                    changedAnything = true;
                    if (!step.isRequiresTimer()) {
                        // Nothing to actively wait for - complete immediately and let the loop advance the dish.
                        completeStepInternal(session, dish, step);
                    }
                }
                case STOVE -> {
                    Optional<StoveResource> freeStove = session.getStoves().stream()
                            .filter(s -> !s.isBusy())
                            .min(Comparator.comparingInt(StoveResource::getStoveIndex));
                    if (freeStove.isPresent()) {
                        StoveResource stove = freeStove.get();
                        stove.setBusy(true);
                        stove.setOccupiedByStepId(step.getId());
                        beginStep(session, step, stove.getStoveIndex());
                        changedAnything = true;
                    }
                    // else: all stoves busy - dish waits its turn, exactly as described ("stove busy -> user waits").
                }
                case USER_ACTION -> {
                    if (!userBusy) {
                        beginStep(session, step, null);
                        userBusy = true; // only one task goes to the user per tick
                        changedAnything = true;
                    }
                    // else: user is occupied with another dish's task - this one waits.
                }
            }
        }
        return changedAnything;
    }

    private void beginStep(CookingSession session, SessionDishStep step, Integer stoveIndex) {
        step.setAssignedStoveIndex(stoveIndex);
        if (step.isRequiresTimer() && step.getTimerSeconds() != null && step.getTimerSeconds() > 0) {
            step.setStatus(StepStatus.TIMER_RUNNING);
            step.setTimerStartAt(Instant.now());
            step.setTimerEndAt(Instant.now().plusSeconds(step.getTimerSeconds()));
            timerService.startTimer(step.getId(), step.getTimerSeconds(), () -> handleTimerElapsed(session.getId(), step.getId()));
        } else {
            step.setStatus(StepStatus.IN_PROGRESS);
        }
    }

    /** Called from a background scheduler thread when a step's timer finishes. Asks the user: next step, or wait? */
    public void handleTimerElapsed(UUID sessionId, UUID stepId) {
        CookingSession session = loadSession(sessionId);
        findStep(session, stepId).ifPresent(step -> {
            if (step.getStatus() == StepStatus.TIMER_RUNNING) {
                step.setStatus(StepStatus.TIMER_COMPLETED_AWAITING_USER);
                sessionRepository.save(session);
                SessionSnapshotDto snapshot = buildSnapshot(session, "Timer's up for \"" + step.getInstruction()
                        + "\". Should I move to the next step, or do you want to wait a bit?");
                notificationService.pushSnapshot(sessionId, snapshot);
            }
        });
    }

    /**
     * User (via voice: "done" / "next") confirms a step is finished. Works for:
     *  - a USER_ACTION or STOVE step with no timer that the user manually finished, or
     *  - a step whose timer already elapsed (TIMER_COMPLETED_AWAITING_USER) and the user says "go to next step".
     */
    @Transactional
    public SessionSnapshotDto completeStep(UUID sessionId, UUID stepId) {
        CookingSession session = loadSession(sessionId);
        SessionDishStep step = findStep(session, stepId)
                .orElseThrow(() -> new ResourceNotFoundException("Step not found: " + stepId));

        if (step.getStatus() != StepStatus.IN_PROGRESS && step.getStatus() != StepStatus.TIMER_COMPLETED_AWAITING_USER) {
            throw new IllegalStateException("Step is not currently active (status=" + step.getStatus() + ")");
        }

        SessionDish dish = findDishOwning(session, step);
        completeStepInternal(session, dish, step);
        sessionRepository.save(session);

        return tick(sessionId);
    }

    /**
     * Lets the user opt into a timer on a step that's already IN_PROGRESS but wasn't pre-assigned one by the
     * recipe (e.g. "should I keep a timer for chopping?" -> "yes, 3 minutes"). Reuses the same
     * TIMER_COMPLETED_AWAITING_USER -> next/wait flow as recipe-driven timers.
     */
    @Transactional
    public SessionSnapshotDto startOptionalTimer(UUID sessionId, UUID stepId, int seconds) {
        if (seconds < 1) {
            throw new IllegalArgumentException("seconds must be at least 1");
        }
        CookingSession session = loadSession(sessionId);
        SessionDishStep step = findStep(session, stepId)
                .orElseThrow(() -> new ResourceNotFoundException("Step not found: " + stepId));
        if (step.getStatus() != StepStatus.IN_PROGRESS) {
            throw new IllegalStateException("Can only start a timer on a step that is IN_PROGRESS (status=" + step.getStatus() + ")");
        }

        step.setRequiresTimer(true);
        step.setTimerSeconds(seconds);
        step.setStatus(StepStatus.TIMER_RUNNING);
        step.setTimerStartAt(Instant.now());
        step.setTimerEndAt(Instant.now().plusSeconds(seconds));
        sessionRepository.save(session);

        timerService.startTimer(step.getId(), seconds, () -> handleTimerElapsed(sessionId, step.getId()));

        SessionSnapshotDto snapshot = buildSnapshot(session, "Timer started for " + seconds + " seconds.");
        notificationService.pushSnapshot(sessionId, snapshot);
        return snapshot;
    }

    /** User says "wait" after a timer completes: keep the resource held, don't advance, just re-confirm state. */
    @Transactional
    public SessionSnapshotDto waitOnStep(UUID sessionId, UUID stepId) {
        CookingSession session = loadSession(sessionId);
        SessionDishStep step = findStep(session, stepId)
                .orElseThrow(() -> new ResourceNotFoundException("Step not found: " + stepId));
        if (step.getStatus() != StepStatus.TIMER_COMPLETED_AWAITING_USER) {
            throw new IllegalStateException("Step has no completed timer awaiting a decision (status=" + step.getStatus() + ")");
        }
        SessionSnapshotDto snapshot = buildSnapshot(session, "Okay, take your time. Just say \"next\" when you're ready to move on.");
        notificationService.pushSnapshot(sessionId, snapshot);
        return snapshot;
    }

    private void completeStepInternal(CookingSession session, SessionDish dish, SessionDishStep step) {
        step.setStatus(StepStatus.COMPLETED);
        timerService.cancelTimer(step.getId());

        if (step.getAssignedStoveIndex() != null) {
            session.getStoves().stream()
                    .filter(s -> s.getStoveIndex() == step.getAssignedStoveIndex())
                    .findFirst()
                    .ifPresent(stove -> {
                        stove.setBusy(false);
                        stove.setOccupiedByStepId(null);
                    });
        }

        dish.setCurrentStepIndex(dish.getCurrentStepIndex() + 1);
        if (dish.getCurrentStepIndex() >= dish.getSteps().size()) {
            dish.setStatus(DishStatus.COMPLETED);
        }
    }

    private boolean isUserBusy(CookingSession session) {
        return session.getDishes().stream()
                .flatMap(d -> d.getSteps().stream())
                .anyMatch(s -> s.getStepType() == StepType.USER_ACTION
                        && (s.getStatus() == StepStatus.IN_PROGRESS || s.getStatus() == StepStatus.TIMER_RUNNING))
                ||
                session.getDishes().stream()
                        .flatMap(d -> d.getSteps().stream())
                        .anyMatch(s -> s.getStatus() == StepStatus.TIMER_COMPLETED_AWAITING_USER);
    }

    private CookingSession loadSession(UUID sessionId) {
        return sessionRepository.findById(sessionId)
                .orElseThrow(() -> new ResourceNotFoundException("Cooking session not found: " + sessionId));
    }

    private Optional<SessionDishStep> findStep(CookingSession session, UUID stepId) {
        return session.getDishes().stream()
                .flatMap(d -> d.getSteps().stream())
                .filter(s -> s.getId().equals(stepId))
                .findFirst();
    }

    private SessionDish findDishOwning(CookingSession session, SessionDishStep step) {
        return session.getDishes().stream()
                .filter(d -> d.getSteps().contains(step))
                .findFirst()
                .orElseThrow(() -> new IllegalStateException("Step is not attached to any dish in this session"));
    }

    private String computeMessage(CookingSession session) {
        return session.getDishes().stream()
                .flatMap(d -> d.getSteps().stream())
                .filter(s -> s.getStatus() == StepStatus.IN_PROGRESS && s.getStepType() == StepType.USER_ACTION)
                .findFirst()
                .map(s -> s.getInstruction())
                .orElseGet(() -> {
                    boolean anyoneCooking = session.getDishes().stream()
                            .flatMap(d -> d.getSteps().stream())
                            .anyMatch(s -> s.getStatus() == StepStatus.TIMER_RUNNING);
                    boolean allDone = session.getDishes().stream().allMatch(d -> d.getStatus() == DishStatus.COMPLETED);
                    if (allDone && !session.getDishes().isEmpty()) return "All dishes are done. Enjoy your meal!";
                    if (anyoneCooking) return "Everything's cooking - I'll let you know when something needs you.";
                    return "Waiting for the next available stove or task.";
                });
    }

    public SessionSnapshotDto buildSnapshot(CookingSession session, String message) {
        SessionSnapshotDto dto = new SessionSnapshotDto();
        dto.sessionId = session.getId();
        dto.sessionStatus = session.getStatus().name();
        dto.message = message;

        for (StoveResource stove : session.getStoves().stream()
                .sorted(Comparator.comparingInt(StoveResource::getStoveIndex)).toList()) {
            StoveStatusDto s = new StoveStatusDto();
            s.stoveIndex = stove.getStoveIndex();
            s.busy = stove.isBusy();
            s.occupiedByStepId = stove.getOccupiedByStepId();
            if (stove.getOccupiedByStepId() != null) {
                findStep(session, stove.getOccupiedByStepId()).ifPresent(step -> {
                    s.occupiedByInstruction = step.getInstruction();
                    if (step.getTimerEndAt() != null) {
                        long remaining = step.getTimerEndAt().getEpochSecond() - Instant.now().getEpochSecond();
                        s.secondsRemaining = Math.max(remaining, 0);
                    }
                });
                s.occupiedByDishName = findDishOwning(session, findStep(session, stove.getOccupiedByStepId()).orElseThrow()).getDishName();
            }
            dto.stoves.add(s);
        }

        session.getDishes().stream()
                .flatMap(d -> d.getSteps().stream().map(s -> Map1.of(d, s)))
                .filter(pair -> pair.step().getStepType() == StepType.USER_ACTION
                        && (pair.step().getStatus() == StepStatus.IN_PROGRESS || pair.step().getStatus() == StepStatus.TIMER_RUNNING
                        || pair.step().getStatus() == StepStatus.TIMER_COMPLETED_AWAITING_USER))
                .findFirst()
                .or(() -> session.getDishes().stream()
                        .flatMap(d -> d.getSteps().stream().map(s -> Map1.of(d, s)))
                        .filter(pair -> pair.step().getStatus() == StepStatus.TIMER_COMPLETED_AWAITING_USER)
                        .findFirst())
                .ifPresent(pair -> {
                    UserTaskDto t = new UserTaskDto();
                    t.sessionDishId = pair.dish().getId();
                    t.stepId = pair.step().getId();
                    t.dishName = pair.dish().getDishName();
                    t.instruction = pair.step().getInstruction();
                    t.stepType = pair.step().getStepType().name();
                    t.status = pair.step().getStatus().name();
                    t.requiresTimer = pair.step().isRequiresTimer();
                    t.timerSeconds = pair.step().getTimerSeconds();
                    dto.currentUserTask = t;
                });

        for (SessionDish dish : session.getDishes()) {
            DishSnapshotDto d = new DishSnapshotDto();
            d.sessionDishId = dish.getId();
            d.dishName = dish.getDishName();
            d.status = dish.getStatus().name();
            d.totalSteps = dish.getSteps().size();
            d.completedSteps = (int) dish.getSteps().stream().filter(s -> s.getStatus() == StepStatus.COMPLETED).count();
            dto.dishes.add(d);
        }

        return dto;
    }

    public StoveStatusDto getStoveStatus(UUID sessionId, int stoveIndex) {
        if (sessionId == null) {
            throw new IllegalArgumentException("Session ID cannot be null");
        }

        if (stoveIndex < 0) {
            throw new IllegalArgumentException("Invalid stove index");
        }

        // 2. Fetch session from DB
        CookingSession session = sessionRepository.findById(sessionId)
                .orElseThrow(() -> new RuntimeException("Session not found"));

        // 3. Get stove from session
        List<StoveResource> stoves = session.getStoves();

        if (stoves == null || stoveIndex >= stoves.size()) {
            throw new RuntimeException("Stove not found for given index");
        }

        StoveResource stove = stoves.get(stoveIndex);

        // 4. Map to DTO
        StoveStatusDto dto = new StoveStatusDto();
        dto.setStoveIndex(stoveIndex);
        dto.setBusy(stove.isBusy());
        return dto;
    }

    /** Tiny local pair record, kept private to avoid polluting the dto package with a throwaway type. */
    private record Map1(SessionDish dish, SessionDishStep step) {
        static Map1 of(SessionDish d, SessionDishStep s) { return new Map1(d, s); }
    }
}

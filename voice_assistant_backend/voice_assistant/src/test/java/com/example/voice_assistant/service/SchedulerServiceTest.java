package com.example.voice_assistant.service;

import com.example.voice_assistant.entity.CookingSession;
import com.example.voice_assistant.entity.SessionDish;
import com.example.voice_assistant.entity.SessionDishStep;
import com.example.voice_assistant.entity.StoveResource;
import com.example.voice_assistant.entity.enums.DishStatus;
import com.example.voice_assistant.entity.enums.SessionStatus;
import com.example.voice_assistant.entity.enums.StepStatus;
import com.example.voice_assistant.entity.enums.StepType;
import com.example.voice_assistant.repository.CookingSessionRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class SchedulerServiceTest {

    private final CookingSessionRepository sessionRepository = mock(CookingSessionRepository.class);
    private final TimerService timerService = mock(TimerService.class);
    private final NotificationService notificationService = mock(NotificationService.class);
    private final CookingSessionService cookingSessionService = mock(CookingSessionService.class);
    private final ObjectProvider<SchedulerService> selfProvider = mock(ObjectProvider.class);

    @Test
    void stoveOnlyAndUserOnlyTasksCanRunAtTheSameTime() {
        CookingSession session = sessionWithStoves(1);
        SessionDish stoveDish = addDish(session, "Rice", 0, StepType.STOVE);
        SessionDish userDish = addDish(session, "Salad", 1, StepType.USER_ACTION);

        SchedulerService scheduler = schedulerFor(session);
        scheduler.tick(session.getId());

        assertTrue(session.getStoves().get(0).isBusy());
        assertEquals(stoveDish.getSteps().get(0).getId(),
                session.getStoves().get(0).getOccupiedByStepId());
        assertEquals(userDish.getSteps().get(0).getId(), session.getUserOccupiedByStepId());
        assertEquals(StepStatus.IN_PROGRESS, stoveDish.getSteps().get(0).getStatus());
        assertEquals(StepStatus.IN_PROGRESS, userDish.getSteps().get(0).getStatus());
    }

    @Test
    void combinedTaskWaitsWithoutPartialReservationThenAcquiresBothTogether() {
        CookingSession session = sessionWithStoves(1);
        SessionDish userDish = addDish(session, "Salad", 0, StepType.USER_ACTION);
        SessionDish combinedDish = addDish(session, "Curry", 1, StepType.STOVE_AND_USER);

        SchedulerService scheduler = schedulerFor(session);
        scheduler.tick(session.getId());

        SessionDishStep combined = combinedDish.getSteps().get(0);
        assertEquals(StepStatus.PENDING, combined.getStatus());
        assertFalse(session.getStoves().get(0).isBusy());
        assertEquals(userDish.getSteps().get(0).getId(), session.getUserOccupiedByStepId());

        scheduler.releaseUser(session.getId());

        assertEquals(StepStatus.COMPLETED, userDish.getSteps().get(0).getStatus());
        assertEquals(StepStatus.IN_PROGRESS, combined.getStatus());
        assertTrue(session.getStoves().get(0).isBusy());
        assertEquals(combined.getId(), session.getStoves().get(0).getOccupiedByStepId());
        assertEquals(combined.getId(), session.getUserOccupiedByStepId());
    }

    @Test
    void freeingUserDuringCombinedStepDoesNotReleaseStoveOrAnotherDishUserTask() {
        CookingSession session = sessionWithStoves(1);
        SessionDish combinedDish = addDish(session, "Curry", 0, StepType.STOVE_AND_USER);
        SessionDish userDish = addDish(session, "Salad", 1, StepType.USER_ACTION);
        SessionDishStep combined = combinedDish.getSteps().get(0);
        SessionDishStep userTask = userDish.getSteps().get(0);

        SchedulerService scheduler = schedulerFor(session);
        scheduler.tick(session.getId());
        scheduler.releaseUser(session.getId());

        assertTrue(session.getStoves().get(0).isBusy());
        assertEquals(combined.getId(), session.getStoves().get(0).getOccupiedByStepId());
        assertEquals(userTask.getId(), session.getUserOccupiedByStepId());
        assertEquals(StepStatus.IN_PROGRESS, combined.getStatus());
        assertEquals(StepStatus.IN_PROGRESS, userTask.getStatus());

        scheduler.completeStoveSteps(session.getId(), java.util.List.of(1, 1));

        assertFalse(session.getStoves().get(0).isBusy());
        assertEquals(StepStatus.COMPLETED, combined.getStatus());
        assertEquals(userTask.getId(), session.getUserOccupiedByStepId());
        assertEquals(StepStatus.IN_PROGRESS, userTask.getStatus());
    }

    @Test
    void duplicateAndInvalidStoveIndicesCompleteEachOccupiedStoveOnlyOnce() {
        CookingSession session = sessionWithStoves(2);
        SessionDish first = addDish(session, "Rice", 0, StepType.STOVE);
        SessionDish second = addDish(session, "Curry", 1, StepType.STOVE);
        SchedulerService scheduler = schedulerFor(session);
        scheduler.tick(session.getId());

        scheduler.completeStoveSteps(session.getId(), java.util.List.of(1, 1, 2, 99));

        assertEquals(StepStatus.COMPLETED, first.getSteps().get(0).getStatus());
        assertEquals(StepStatus.COMPLETED, second.getSteps().get(0).getStatus());
        assertEquals(1, first.getCurrentStepIndex());
        assertEquals(1, second.getCurrentStepIndex());
        assertTrue(session.getStoves().stream().noneMatch(StoveResource::isBusy));
    }

    @Test
    void invalidOrUnoccupiedStoveDoesNotChangeSessionResources() {
        CookingSession session = sessionWithStoves(1);
        SessionDish dish = addDish(session, "Rice", 0, StepType.STOVE);
        SchedulerService scheduler = schedulerFor(session);
        scheduler.tick(session.getId());

        scheduler.completeStoveSteps(session.getId(), java.util.List.of(4));

        assertTrue(session.getStoves().get(0).isBusy());
        assertEquals(StepStatus.IN_PROGRESS, dish.getSteps().get(0).getStatus());
        verify(timerService, never()).cancelTimer(dish.getSteps().get(0).getId());
    }

    @Test
    void schedulesOneSixMinuteReminderForAnActiveUserTask() {
        CookingSession session = sessionWithStoves(1);
        SessionDish dish = addDish(session, "Salad", 0, StepType.USER_ACTION);
        SchedulerService scheduler = schedulerFor(session);

        scheduler.tick(session.getId());
        scheduler.tick(session.getId());

        verify(timerService, times(1)).startUserReminder(
                eq(session.getId()),
                eq(dish.getSteps().get(0).getId()),
                eq(Duration.ofMinutes(6)),
                any(Runnable.class));
    }

    @Test
    void reminderRepeatsTheHeldTaskWithoutReleasingTheUser() {
        CookingSession session = sessionWithStoves(1);
        SessionDish dish = addDish(session, "Salad", 0, StepType.USER_ACTION);
        ObjectProvider<SchedulerService> provider = mock(ObjectProvider.class);
        SchedulerService scheduler = new SchedulerService(
                sessionRepository, timerService, notificationService, cookingSessionService, provider);
        when(provider.getObject()).thenReturn(scheduler);
        when(sessionRepository.findByIdForUpdate(session.getId())).thenReturn(Optional.of(session));
        when(sessionRepository.save(any(CookingSession.class))).thenAnswer(invocation -> invocation.getArgument(0));
        List<Runnable> reminders = new ArrayList<>();
        org.mockito.Mockito.doAnswer(invocation -> {
            reminders.add(invocation.getArgument(3));
            return null;
        }).when(timerService).startUserReminder(
                eq(session.getId()),
                eq(dish.getSteps().get(0).getId()),
                eq(Duration.ofMinutes(6)),
                any(Runnable.class));

        scheduler.tick(session.getId());
        reminders.get(0).run();

        assertEquals(dish.getSteps().get(0).getId(), session.getUserOccupiedByStepId());
        verify(notificationService, times(2)).pushSnapshot(eq(session.getId()), any());
    }

    @Test
    void cancellationClearsReservationsCancelsStepsAndStopsTimers() {
        CookingSession session = sessionWithStoves(1);
        SessionDish dish = addDish(session, "Curry", 0, StepType.STOVE_AND_USER);
        SchedulerService scheduler = schedulerFor(session);
        scheduler.tick(session.getId());

        scheduler.cancelSession(session.getId());

        assertEquals(SessionStatus.CANCELLED, session.getStatus());
        assertEquals(DishStatus.CANCELLED, dish.getStatus());
        assertEquals(StepStatus.CANCELLED, dish.getSteps().get(0).getStatus());
        assertNull(session.getUserOccupiedByStepId());
        assertFalse(session.getStoves().get(0).isBusy());
        assertNull(session.getStoves().get(0).getOccupiedByStepId());
        verify(timerService).cancelTimersForSession(session.getId());

        scheduler.tick(session.getId());
        scheduler.handleTimerElapsed(session.getId(), dish.getSteps().get(0).getId());

        assertEquals(StepStatus.CANCELLED, dish.getSteps().get(0).getStatus());
    }

    @Test
    void staleHeartbeatCancellationRechecksTheCurrentHeartbeat() {
        CookingSession session = sessionWithStoves(1);
        session.setLastHeartbeatAt(Instant.now());
        SchedulerService scheduler = schedulerFor(session);

        scheduler.cancelIfHeartbeatExpired(session.getId(), Instant.now().minusSeconds(1));

        assertEquals(SessionStatus.ACTIVE, session.getStatus());
        verify(timerService, never()).cancelTimersForSession(session.getId());
    }

    @Test
    void quietTickDispatchesButNeverNotifiesSockets() {
        CookingSession session = sessionWithStoves(1);
        addDish(session, "Rice", 0, StepType.STOVE);
        SchedulerService scheduler = schedulerFor(session);

        scheduler.tickQuietly(session.getId());

        assertTrue(session.getStoves().get(0).isBusy(), "the dispatch still happens");
        verify(notificationService, never()).pushSnapshot(eq(session.getId()), any());
    }

    @Test
    void finishingTheLastStepOfADishAnnouncesItAndTheEndOfTheMeal() {
        CookingSession session = sessionWithStoves(1);
        SessionDish dish = addDish(session, "Dal Tadka", 0, StepType.USER_ACTION);
        SchedulerService scheduler = schedulerFor(session);
        // Mirror the real CookingSessionService: the session is completed as soon as the last dish is.
        org.mockito.Mockito.doAnswer(invocation -> {
            CookingSession s = invocation.getArgument(0);
            if (!s.getDishes().isEmpty()
                    && s.getDishes().stream().allMatch(d -> d.getStatus() == DishStatus.COMPLETED)) {
                s.setStatus(SessionStatus.COMPLETED);
            }
            return null;
        }).when(cookingSessionService).markSessionCompletedIfAllDishesDone(any(CookingSession.class));

        scheduler.tick(session.getId());
        com.example.voice_assistant.dto.response.SessionSnapshotDto snapshot =
                scheduler.completeStep(session.getId(), dish.getSteps().get(0).getId());

        assertEquals(DishStatus.COMPLETED, dish.getStatus());
        assertEquals(SessionStatus.COMPLETED, session.getStatus(), "the session ends once the meal is cooked");
        assertTrue(snapshot.message.contains("Dal Tadka"), snapshot.message);
        assertTrue(snapshot.message.contains("is done"), snapshot.message);
        assertTrue(snapshot.message.contains("Happy meal"), snapshot.message);
    }

    @Test
    void finishingADishAnnouncesItBeforeTheNextDishInstruction() {
        CookingSession session = sessionWithStoves(1);
        SessionDish jeera = twoStepUserDish(session, "Jeera Rice", 0);
        addDish(session, "Paneer Curry", 1, StepType.USER_ACTION);
        SchedulerService scheduler = schedulerFor(session);

        scheduler.tick(session.getId());
        scheduler.completeStep(session.getId(), jeera.getSteps().get(0).getId());
        com.example.voice_assistant.dto.response.SessionSnapshotDto snapshot =
                scheduler.completeStep(session.getId(), jeera.getSteps().get(1).getId());

        assertEquals(DishStatus.COMPLETED, jeera.getStatus());
        assertTrue(snapshot.message.startsWith("\"Jeera Rice\" is done!"), snapshot.message);
        assertTrue(snapshot.message.contains("Prepare Paneer Curry"), snapshot.message);
    }

    @Test
    void nextDuringARunningTimerCompletesTheStepEarlyAndCancelsTheTimer() {
        CookingSession session = sessionWithStoves(1);
        SessionDish dish = addDish(session, "Masala Chai", 0, StepType.STOVE_AND_USER);
        SessionDishStep step = dish.getSteps().get(0);
        step.setRequiresTimer(true);
        step.setTimerSeconds(120);
        SchedulerService scheduler = schedulerFor(session);

        scheduler.tick(session.getId());
        assertEquals(StepStatus.TIMER_RUNNING, step.getStatus());

        scheduler.completeStep(session.getId(), step.getId());

        assertEquals(StepStatus.COMPLETED, step.getStatus());
        assertEquals(DishStatus.COMPLETED, dish.getStatus());
        verify(timerService).cancelTimer(step.getId());
    }

    private SchedulerService schedulerFor(CookingSession session) {
        when(sessionRepository.findByIdForUpdate(session.getId())).thenReturn(Optional.of(session));
        when(sessionRepository.findById(session.getId())).thenReturn(Optional.of(session));
        when(sessionRepository.save(any(CookingSession.class))).thenAnswer(invocation -> invocation.getArgument(0));
        return new SchedulerService(
                sessionRepository, timerService, notificationService, cookingSessionService, selfProvider);
    }

    private CookingSession sessionWithStoves(int count) {
        CookingSession session = new CookingSession();
        session.setId(UUID.randomUUID());
        session.setStatus(SessionStatus.ACTIVE);
        session.setNumberOfStoves(count);
        for (int index = 1; index <= count; index++) {
            session.getStoves().add(new StoveResource(session, index));
        }
        return session;
    }

    private SessionDish twoStepUserDish(CookingSession session, String name, int order) {
        SessionDish dish = new SessionDish();
        dish.setId(UUID.randomUUID());
        dish.setSession(session);
        dish.setDishName(name);
        dish.setPriorityOrder(order);
        dish.setStatus(DishStatus.PENDING);
        for (int number = 1; number <= 2; number++) {
            SessionDishStep step = new SessionDishStep();
            step.setId(UUID.randomUUID());
            step.setStepNumber(number);
            step.setInstruction("Prepare " + name + " step " + number);
            step.setStepType(StepType.USER_ACTION);
            dish.addStep(step);
        }
        session.getDishes().add(dish);
        return dish;
    }

    private SessionDish addDish(CookingSession session, String name, int order, StepType type) {
        SessionDish dish = new SessionDish();
        dish.setId(UUID.randomUUID());
        dish.setSession(session);
        dish.setDishName(name);
        dish.setPriorityOrder(order);
        dish.setStatus(DishStatus.PENDING);
        SessionDishStep step = new SessionDishStep();
        step.setId(UUID.randomUUID());
        step.setStepNumber(1);
        step.setInstruction("Prepare " + name);
        step.setStepType(type);
        dish.addStep(step);
        session.getDishes().add(dish);
        return dish;
    }
}

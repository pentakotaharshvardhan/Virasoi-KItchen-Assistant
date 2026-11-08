package com.example.voice_assistant.service;

import com.example.voice_assistant.entity.*;
import com.example.voice_assistant.entity.enums.DishStatus;
import com.example.voice_assistant.entity.enums.SessionStatus;
import com.example.voice_assistant.exception.ResourceNotFoundException;
import com.example.voice_assistant.properties.KitchenLimits;
import com.example.voice_assistant.properties.KitchenProperties;
import com.example.voice_assistant.repository.CookingSessionRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.UUID;

@Service
public class CookingSessionService {

    private final CookingSessionRepository sessionRepository;
    private final RecipeService recipeService;
    private final KitchenProperties kitchenProperties;

    public CookingSessionService(CookingSessionRepository sessionRepository, RecipeService recipeService,
                                  KitchenProperties kitchenProperties) {
        this.sessionRepository = sessionRepository;
        this.recipeService = recipeService;
        this.kitchenProperties = kitchenProperties;
    }

    @Transactional
    public CookingSession startSession(String userId, int numberOfStoves) {
        if (numberOfStoves < 1) {
            throw new IllegalArgumentException("numberOfStoves must be at least 1");
        }
        if (numberOfStoves > KitchenLimits.MAX_STOVES) {
            throw new IllegalArgumentException("numberOfStoves must not exceed " + KitchenLimits.MAX_STOVES);
        }
        CookingSession session = new CookingSession();
        session.setUserId(userId);
        session.setNumberOfStoves(numberOfStoves);
        session.setStatus(SessionStatus.ACTIVE);

        for (int i = 1; i <= numberOfStoves; i++) {
            session.getStoves().add(new StoveResource(session, i));
        }

        return sessionRepository.save(session);
    }

    public CookingSession getById(UUID sessionId) {
        return sessionRepository.findById(sessionId)
                .orElseThrow(() -> new ResourceNotFoundException("Cooking session not found: " + sessionId));
    }

    /**
     * Adds a dish to an in-progress session: finds (or AI-generates) the recipe, scales every
     * ingredient/step for the requested number of serves, and appends it to the session's dish queue.
     * The caller is responsible for triggering a scheduler tick afterwards.
     */
    @Transactional
    public SessionDish addDish(CookingSession session, String dishName, int servesRequested) {
        if (servesRequested < 1) {
            throw new IllegalArgumentException("servesRequested must be at least 1");
        }
        CookingSession lockedSession = sessionRepository.findByIdForUpdate(session.getId())
                .orElseThrow(() -> new ResourceNotFoundException("Cooking session not found: " + session.getId()));

        // "ready" can be answered twice (retry, a second device, a slow request repeated).
        // Re-enqueueing the same dish would give the scheduler a duplicate step queue, so the
        // already-queued dish is simply returned - before the limit check, so a repeat can
        // never fail with "too many dishes".
        String requested = dishName == null ? "" : dishName.trim();
        for (SessionDish existing : lockedSession.getDishes()) {
            if (existing.getDishName() != null
                    && !requested.isEmpty()
                    && existing.getDishName().trim().equalsIgnoreCase(requested)) {
                return existing;
            }
        }

        if (lockedSession.getDishes().size() >= KitchenLimits.MAX_DISHES) {
            throw new IllegalStateException("A cooking session can have at most " + KitchenLimits.MAX_DISHES + " dishes");
        }

        Recipe recipe = recipeService.findOrGenerate(dishName, lockedSession.getUserId());

        SessionDish dish = new SessionDish();
        dish.setSession(lockedSession);
        dish.setRecipe(recipe);
        dish.setDishName(recipe.getDishName());
        dish.setServesRequested(servesRequested);
        dish.setPriorityOrder(lockedSession.getDishes().size());
        dish.setStatus(DishStatus.PENDING);
        dish.setCurrentStepIndex(0);

        for (RecipeStep rs : recipe.getSteps()) {
            SessionDishStep sds = new SessionDishStep();
            sds.setStepNumber(rs.getStepNumber());
            sds.setInstruction(rs.getInstruction());
            sds.setStepType(rs.getStepType());
            sds.setRequiresTimer(rs.isRequiresTimer());
            sds.setTimerSeconds(scaleTimer(rs.getBaseTimerSeconds(), rs.isScalesWithServes(), servesRequested));
            sds.setIngredient(rs.getIngredient()); // ADD
            dish.addStep(sds);
        }

        lockedSession.getDishes().add(dish);
        sessionRepository.save(lockedSession);
        return dish;
    }

    /** Scales ingredient quantity for the requested number of serves (recipes are always authored for 1 serve). */
    public BigDecimal scaleIngredient(BigDecimal quantityPerServe, int servesRequested) {
        if (quantityPerServe == null) return null;
        return quantityPerServe.multiply(BigDecimal.valueOf(servesRequested));
    }

    /** Scales a step's timer duration. Fixed-duration steps (scalesWithServes=false) are left untouched. */
    private Integer scaleTimer(Integer baseSeconds, boolean scalesWithServes, int servesRequested) {
        if (baseSeconds == null) return null;
        if (!scalesWithServes || servesRequested <= kitchenProperties.getBaseServes()) {
            return baseSeconds;
        }
        int extraServes = servesRequested - kitchenProperties.getBaseServes();
        double factor = 1.0 + (extraServes * kitchenProperties.getTimerScaleFactorPerServe());
        return (int) Math.round(baseSeconds * factor);
    }

    @Transactional
    public void markSessionCompletedIfAllDishesDone(CookingSession session) {
        boolean allDone = session.getDishes().stream().allMatch(d -> d.getStatus() == DishStatus.COMPLETED);
        if (allDone && !session.getDishes().isEmpty()) {
            session.setStatus(SessionStatus.COMPLETED);
            sessionRepository.save(session);
        }
    }
}

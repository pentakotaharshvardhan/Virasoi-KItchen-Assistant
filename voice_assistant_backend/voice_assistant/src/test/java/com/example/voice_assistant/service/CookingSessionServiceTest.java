package com.example.voice_assistant.service;

import com.example.voice_assistant.entity.CookingSession;
import com.example.voice_assistant.entity.SessionDish;
import com.example.voice_assistant.properties.KitchenProperties;
import com.example.voice_assistant.repository.CookingSessionRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class CookingSessionServiceTest {

    @Mock
    private CookingSessionRepository sessionRepository;

    @Mock
    private RecipeService recipeService;

    @Mock
    private KitchenProperties kitchenProperties;

    @InjectMocks
    private CookingSessionService cookingSessionService;

    @Test
    void startSessionRejectsMoreThanFourStoves() {
        assertThrows(IllegalArgumentException.class,
                () -> cookingSessionService.startSession("user-1", 5));

        verify(sessionRepository, never()).save(any(CookingSession.class));
    }

    @Test
    void startSessionCreatesFourStoveResources() {
        when(sessionRepository.save(any(CookingSession.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        CookingSession session = cookingSessionService.startSession("user-1", 4);

        assertEquals(4, session.getNumberOfStoves());
        assertEquals(4, session.getStoves().size());
    }

    @Test
    void addDishRejectsFifthDishBeforeLookingUpOrGeneratingRecipe() {
        CookingSession session = new CookingSession();
        session.setId(UUID.randomUUID());
        for (int i = 0; i < 4; i++) {
            session.getDishes().add(new SessionDish());
        }
        when(sessionRepository.findByIdForUpdate(session.getId())).thenReturn(Optional.of(session));

        assertThrows(IllegalStateException.class,
                () -> cookingSessionService.addDish(session, "Dish five", 2));

        verify(recipeService, never()).findOrGenerate(org.mockito.ArgumentMatchers.anyString(),
                org.mockito.ArgumentMatchers.anyString());
    }
}

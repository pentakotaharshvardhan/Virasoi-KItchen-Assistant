package com.example.voice_assistant.controller;

import com.example.voice_assistant.entity.AppUser;
import com.example.voice_assistant.security.AppUserDetails;
import com.example.voice_assistant.service.RecipeService;
import org.junit.jupiter.api.Test;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.*;

class RecipeControllerTest {

    private final RecipeService recipeService = mock(RecipeService.class);
    private final RecipeController controller = new RecipeController(recipeService);

    @Test
    void listByUserRejectsAUserOtherThanTheAuthenticatedPrincipal() {
        Authentication authentication = authentication(UUID.randomUUID());

        assertThrows(AccessDeniedException.class,
                () -> controller.listByUser(UUID.randomUUID().toString(), authentication));
        verifyNoInteractions(recipeService);
    }

    @Test
    void listAllUsesTheAuthenticatedUsersId() {
        UUID userId = UUID.randomUUID();
        Authentication authentication = authentication(userId);

        controller.listAll(authentication);

        verify(recipeService).listByUserId(userId.toString());
    }

    private Authentication authentication(UUID userId) {
        AppUser user = new AppUser();
        user.setId(userId);
        user.setUsername("chef");
        user.setPasswordHash("hash");
        return new UsernamePasswordAuthenticationToken(
                new AppUserDetails(user), "credentials");
    }
}

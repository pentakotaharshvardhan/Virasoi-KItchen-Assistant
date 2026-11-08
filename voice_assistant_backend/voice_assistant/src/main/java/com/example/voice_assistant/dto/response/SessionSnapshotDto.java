package com.example.voice_assistant.dto.response;

import com.fasterxml.jackson.annotation.JsonIgnore;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/** Full picture of a session: sent after every scheduler tick, over the WebSocket and from the status REST endpoint. */
public class SessionSnapshotDto {
    public UUID sessionId;
    public String sessionStatus;
    public List<StoveStatusDto> stoves = new ArrayList<>();
    public UserTaskDto currentUserTask; // null when the user has nothing to do right now
    public List<DishSnapshotDto> dishes = new ArrayList<>();
    public String message; // human-readable prompt the assistant should speak next
    public String messageAudioBase64; // Base64 MP3 (Google Cloud TTS) of `message` - null if TTS is unavailable/failed

    /** Set by NotificationService.pushSnapshot(): every socket of the session has already been
     *  given this frame, so the WebSocket handler must not send it to the requester a second
     *  time (that double delivery is what made one "next" show up twice in the chat). */
    @JsonIgnore
    public boolean alreadyPushed = false;
}

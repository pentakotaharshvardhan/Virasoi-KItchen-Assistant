package com.example.voice_assistant.dto.response;

import java.util.UUID;

public class StoveStatusDto {
    public int stoveIndex;
    public boolean busy;
    public UUID occupiedByStepId;
    public String occupiedByDishName;
    public String occupiedByInstruction;
    public Long secondsRemaining;

    public int getStoveIndex() {
        return stoveIndex;
    }

    public void setStoveIndex(int stoveIndex) {
        this.stoveIndex = stoveIndex;
    }

    public boolean isBusy() {
        return busy;
    }

    public void setBusy(boolean busy) {
        this.busy = busy;
    }


    public String getOccupiedByDishName() {
        return occupiedByDishName;
    }

    public void setOccupiedByDishName(String occupiedByDishName) {
        this.occupiedByDishName = occupiedByDishName;
    }

    public String getOccupiedByInstruction() {
        return occupiedByInstruction;
    }

    public void setOccupiedByInstruction(String occupiedByInstruction) {
        this.occupiedByInstruction = occupiedByInstruction;
    }

    public Long getSecondsRemaining() {
        return secondsRemaining;
    }

    public void setSecondsRemaining(Long secondsRemaining) {
        this.secondsRemaining = secondsRemaining;
    }
}

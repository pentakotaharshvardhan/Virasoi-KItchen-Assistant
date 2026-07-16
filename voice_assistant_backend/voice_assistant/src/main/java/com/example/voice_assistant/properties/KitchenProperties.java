package com.example.voice_assistant.properties;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "kitchen.recipe")
public class KitchenProperties {
    private int baseServes = 1;
    private double timerScaleFactorPerServe = 0.12;

    public int getBaseServes() { return baseServes; }
    public void setBaseServes(int baseServes) { this.baseServes = baseServes; }
    public double getTimerScaleFactorPerServe() { return timerScaleFactorPerServe; }
    public void setTimerScaleFactorPerServe(double timerScaleFactorPerServe) { this.timerScaleFactorPerServe = timerScaleFactorPerServe; }
}

package com.example.voice_assistant.entity.enums;

/**
 * Classifies what resource a cooking step needs, which drives the
 * scheduling engine (see SchedulerService):
 *
 *  STOVE       - needs one of the limited stove resources (e.g. simmer, fry, boil)
 *  USER_ACTION - needs the user's hands/attention but no stove (e.g. chop, whisk, plate)
 *  PASSIVE     - needs neither the stove nor the user right now (e.g. "let dough rest",
 *                "marinate in the fridge") - it just runs in the background on a timer
 */
public enum StepType {
    STOVE,
    USER_ACTION,
    PASSIVE
}

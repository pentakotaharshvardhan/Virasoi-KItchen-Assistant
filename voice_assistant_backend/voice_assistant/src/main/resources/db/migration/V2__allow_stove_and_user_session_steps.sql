DO $$
BEGIN
    IF to_regclass('session_dish_steps') IS NOT NULL THEN
        ALTER TABLE session_dish_steps
            DROP CONSTRAINT IF EXISTS session_dish_steps_step_type_check;

        ALTER TABLE session_dish_steps
            ADD CONSTRAINT session_dish_steps_step_type_check
            CHECK (step_type IN ('STOVE', 'USER_ACTION', 'STOVE_AND_USER', 'PASSIVE'));
    END IF;
END;
$$;

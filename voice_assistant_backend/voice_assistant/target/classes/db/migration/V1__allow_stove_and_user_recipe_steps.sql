DO $$
BEGIN
    IF to_regclass('recipe_steps') IS NOT NULL THEN
        ALTER TABLE recipe_steps
            DROP CONSTRAINT IF EXISTS recipe_steps_step_type_check;

        ALTER TABLE recipe_steps
            ADD CONSTRAINT recipe_steps_step_type_check
            CHECK (step_type IN ('STOVE', 'USER_ACTION', 'STOVE_AND_USER', 'PASSIVE'));
    END IF;
END;
$$;

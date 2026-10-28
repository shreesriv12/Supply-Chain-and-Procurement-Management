-- Forward migration: procurement-agent no-action status and RAG privileges.
-- Safe to re-run. Do not delete or reseed the database volume.

BEGIN;

ALTER TABLE public.agent_run
    DROP CONSTRAINT IF EXISTS agent_run_status_check;

ALTER TABLE public.agent_run
    ADD CONSTRAINT agent_run_status_check
    CHECK (
        status IN (
            'RUNNING',
            'AWAITING_APPROVAL',
            'APPROVED',
            'REJECTED',
            'FAILED',
            'NO_ACTION_REQUIRED'
        )
    );

-- RAG runs as app_admin and needs permission to use vector functions.
GRANT USAGE ON SCHEMA public TO app_admin;

GRANT EXECUTE ON FUNCTION
    public.vector(vector, integer, boolean)
    TO app_admin;

GRANT EXECUTE ON FUNCTION
    public.cosine_distance(vector, vector)
    TO app_admin;

COMMIT;
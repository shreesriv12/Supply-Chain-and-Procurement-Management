\echo '=== Database/version ==='
SELECT current_database() AS database_name, version() AS postgres_version;

\echo '=== Base tables ==='
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
ORDER BY table_name;

\echo '=== Primary, unique and foreign-key constraints ==='
SELECT tc.table_name, tc.constraint_name, tc.constraint_type
FROM information_schema.table_constraints AS tc
WHERE tc.constraint_schema = 'public'
  AND tc.constraint_type IN ('PRIMARY KEY', 'UNIQUE', 'FOREIGN KEY', 'CHECK')
ORDER BY tc.table_name, tc.constraint_type, tc.constraint_name;

\echo '=== Reporting views ==='
SELECT table_name
FROM information_schema.views
WHERE table_schema = 'public'
ORDER BY table_name;

\echo '=== Index definitions ==='
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;

\echo '=== Triggers ==='
SELECT event_object_table AS table_name, trigger_name, event_manipulation,
       action_timing, action_statement
FROM information_schema.triggers
WHERE trigger_schema = 'public'
ORDER BY event_object_table, trigger_name;

\echo '=== Functions and procedures ==='
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE specific_schema = 'public'
ORDER BY routine_type, routine_name;

\echo '=== Application roles ==='
SELECT rolname, rolsuper, rolcanlogin
FROM pg_roles
WHERE rolname IN ('scm_admin', 'app_admin', 'app_procurement',
                   'app_warehouse', 'app_finance', 'app_viewer', 'nl_readonly')
ORDER BY rolname;

\echo '=== Agent statuses supported by the database ==='
SELECT pg_get_constraintdef(oid) AS agent_run_status_constraint
FROM pg_constraint
WHERE conrelid = 'public.agent_run'::regclass
  AND conname = 'agent_run_status_check';

\echo '=== Vector permissions used by the RAG endpoint ==='
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS arguments,
       has_function_privilege('app_admin', p.oid, 'EXECUTE') AS app_admin_can_execute
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND ((p.proname = 'vector' AND pg_get_function_identity_arguments(p.oid) = 'vector, integer, boolean')
    OR (p.proname = 'cosine_distance' AND pg_get_function_identity_arguments(p.oid) = 'vector, vector'))
ORDER BY p.proname;
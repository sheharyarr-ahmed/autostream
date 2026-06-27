-- AutoStream observability schema (migration 0002)
-- Apply with: psql "$SUPABASE_URL" -f supabase/migrations/0002_exec_id_text.sql
--   (or paste into the Supabase SQL Editor)
--
-- n8n execution ids are sequential integers (e.g. "24"), not UUIDs. Migration
-- 0001 typed the run-id columns as uuid, which contradicted its own comment
-- ("id = n8n execution id") and rejected every insert. Store them as text so a
-- row links back to the real n8n execution page. Tables are empty (no successful
-- insert ever landed), so these ALTERs are non-destructive.

alter table llm_calls     alter column workflow_run_id type text;
alter table workflow_runs alter column id              type text;
alter table error_log     alter column workflow_run_id type text;

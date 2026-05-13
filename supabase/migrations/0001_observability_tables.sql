-- AutoStream observability schema (migration 0001)
-- Apply with: psql "$SUPABASE_URL" -f supabase/migrations/0001_observability_tables.sql
--
-- Three tables make every LLM call, every workflow execution, and every error
-- inspectable from outside the n8n container. See ADR 0007.

create extension if not exists "pgcrypto";

-- =============================================================================
-- llm_calls: one row per Anthropic call
-- =============================================================================
create table if not exists llm_calls (
  id              uuid primary key default gen_random_uuid(),
  workflow_id     text not null,
  workflow_run_id uuid not null,
  model           text not null,
  prompt_tokens   int  not null,
  output_tokens   int  not null,
  duration_ms     int  not null,
  cost_usd        numeric(10, 6) not null,
  input           jsonb not null,
  output          jsonb not null,
  status          text not null check (status in ('ok', 'parse_error', 'api_error')),
  created_at      timestamptz not null default now()
);

create index if not exists llm_calls_workflow_created_idx
  on llm_calls (workflow_id, created_at desc);

create index if not exists llm_calls_status_idx
  on llm_calls (status) where status != 'ok';

comment on table llm_calls is 'One row per Anthropic API call. Append-only by convention.';

-- =============================================================================
-- workflow_runs: one row per workflow execution
-- =============================================================================
create table if not exists workflow_runs (
  id          uuid primary key,
  workflow_id text not null,
  status      text not null check (status in ('ok', 'error', 'skipped_empty')),
  duration_ms int  not null,
  started_at  timestamptz not null,
  ended_at    timestamptz not null,
  meta        jsonb not null default '{}'::jsonb
);

create index if not exists workflow_runs_workflow_started_idx
  on workflow_runs (workflow_id, started_at desc);

comment on table workflow_runs is 'One row per workflow execution. id = n8n execution id.';

-- =============================================================================
-- error_log: one row per failure event (written by the shared error workflow)
-- =============================================================================
create table if not exists error_log (
  id              uuid primary key default gen_random_uuid(),
  workflow_id     text not null,
  workflow_run_id uuid,
  kind            text not null,
  error_message   text not null,
  context         jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now()
);

create index if not exists error_log_workflow_created_idx
  on error_log (workflow_id, created_at desc);

comment on table error_log is 'One row per failure event. kind groups related errors (e.g. anthropic_429, rss_feed_error, imap_tls).';

-- =============================================================================
-- content_briefs: dedup horizon for workflow 2 (daily content brief)
-- =============================================================================
create table if not exists content_briefs (
  guid       text primary key,
  title      text not null,
  link       text not null,
  source     text not null,
  pub_date   timestamptz,
  selected   boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists content_briefs_created_idx
  on content_briefs (created_at desc);

comment on table content_briefs is 'Workflow 2 (daily content brief) dedup horizon. Rows older than 7 days are eligible for archival.';

-- =============================================================================
-- email_corrections: human-labeled overrides for workflow 3 (for accuracy queries)
-- =============================================================================
create table if not exists email_corrections (
  message_id        text primary key,
  llm_classified_as text not null,
  human_correct_to  text not null,
  created_at        timestamptz not null default now()
);

comment on table email_corrections is 'Manual corrections to workflow 3 classifications. Used to compute classification accuracy over time.';

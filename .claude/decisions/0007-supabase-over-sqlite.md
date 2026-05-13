# ADR 0007 — Observability: Supabase Postgres over local SQLite

**Status:** Accepted (Phase 1)
**Date:** 2026-05-14

## Context

The observability layer (`llm_calls`, `workflow_runs`, `error_log`) is the load-bearing instrument for AutoStream's "every LLM call is observable" claim. Two storage options:

- **Local SQLite** — single file in `n8n_data/`, zero setup, fastest reads from inside the container.
- **Supabase Postgres (free tier)** — managed Postgres, remote-inspectable via REST and direct psql, 500MB storage on free tier.

## Decision

Use **Supabase Postgres** for observability. n8n's own internal Postgres handles n8n's execution data and remains co-located in the docker-compose stack.

## Rationale

- **Remote inspectability.** Sheharyar needs to run analytics queries (`select sum(cost_usd)` etc.) without `docker exec` into the container. The README's "What it makes measurable" section is only credible if those queries are runnable by a reviewer too.
- **Survives container restarts cleanly.** SQLite in a Docker volume survives restarts but is tied to the container's volume — losing the volume loses the history. Supabase is durable independent of the n8n deployment.
- **Free tier covers demo volume comfortably.** 500MB DB at ~500 bytes/row = ~1M rows headroom. Phase 1 won't produce more than ~10k rows.
- **Standard Postgres SQL.** Queries written today work unchanged at Phase 2's scale (when AutoStream may have its own dedicated Postgres). SQLite-specific quirks (no `RETURNING`, weaker JSON path syntax) would have to be unlearned later.
- **Portfolio signal.** "Logs to Supabase" is a phrase that resonates with the small-team operator audience.

## Consequences

- **Positive**: see rationale.
- **Negative**: a network hop on every LLM call to write the log. ~50ms added latency. Acceptable: workflow 1's 2s budget tolerates it; workflows 2 and 3 are insensitive.
- **Negative**: another service to keep alive. Mitigated by Supabase's free-tier reliability + AutoStream's read-only nature of the table (no app depends on it for execution).

## Schema location

`supabase/migrations/0001_observability_tables.sql` — applied with `psql "$SUPABASE_URL" -f supabase/migrations/0001_observability_tables.sql`.

## Reconsideration triggers

- Supabase free tier changes drop below useful thresholds → migrate to self-hosted Postgres (Phase 2 may do this anyway as part of n8n DB separation per `SCALING.md` Phase B).
- Phase 3 multi-tenant introduces per-tenant Supabase projects → that's a Phase 3 ADR, not a change here.

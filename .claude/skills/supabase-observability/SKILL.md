---
name: supabase-observability
description: Use when reading from or writing to the Supabase observability tables (llm_calls, workflow_runs, error_log) — schema, insert payloads from n8n HTTP nodes, common analytics queries. Triggers on keywords like supabase, observability, llm_calls, workflow_runs, error_log.
tier: 1
---

Skill metadata only. Load `core.md` for schema + insert templates; `reference/retention-queries.md` for retention + index-tuning patterns.

## Quick references

- Schema + insert templates: `core.md`
- Retention + index tuning: `reference/retention-queries.md`
- Migration file: `supabase/migrations/0001_observability_tables.sql`
- ADR: `.claude/decisions/0007-supabase-over-sqlite.md`

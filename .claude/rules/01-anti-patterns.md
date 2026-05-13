# Rule 01 — Anti-Patterns (forbidden choices)

These were considered and rejected by ADR. Don't reintroduce them.

## Forbidden services / dependencies

- **NewsAPI** for content ingestion. Use RSS (no key, no quota). ADR 0004.
- **Gmail Pub/Sub** for email ingestion. Use IMAP polling (no GCP project). ADR 0005.
- **Local SQLite** for observability. Use Supabase Postgres (remote-inspectable). ADR 0007.
- **Any paid SaaS tier** during Phase 1. The demo runs on free tiers only. See `05-cost-control.md`.

## Forbidden workflow patterns

- **Unbounded retry** on any external call. Max 2 attempts, period. After the second failure, route to the error workflow. See `03-workflow-design.md`.
- **Silent failure** — every error must land in `error_log` AND fire a Slack alert to `#autostream-errors`. No catch-and-swallow.
- **Missing Zod-equivalent validation** on any LLM output. Parse errors must be caught and logged with `status='parse_error'`. See ADR 0008.
- **Shared state in n8n** between workflows. The three workflows are isolated; cross-talk happens only via Postgres. ADR 0002.

## Forbidden architectural shifts

- **Replacing n8n with a code framework** (LangGraph, VoltAgent, LangChain) — pivots the portfolio thesis. If a code-framework asset is wanted, it's a separate Project Auto-Stream asset, not AutoStream.
- **One mega-workflow** that handles all three triggers. The three are intentionally independent so one can fail without taking down the others. ADR 0002.
- **Storing secrets in workflow JSON exports**. Always reference `$env.<KEY>` or n8n credentials. Workflow JSONs go in git; secrets do not.

## Forbidden output / prompt patterns

- **Returning prose instead of JSON** from LLM nodes. Always system-prompt for JSON-only output and validate with Zod-equivalent.
- **Using Opus 4.7 for routing/classification** when Haiku 4.5 suffices. Opus is reserved for the critic node in workflow 2. ADR 0006.
- **Logging full payloads containing secrets**. Redact before insert into `llm_calls.input`.

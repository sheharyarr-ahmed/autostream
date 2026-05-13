# ADR 0002 — Architecture: three isolated workflows over one mega-workflow

**Status:** Accepted (Phase 1)
**Date:** 2026-05-14

## Context

AutoStream ships three pieces of automation (lead qualification, daily content brief, email classification). Two architectural shapes were considered:

- **Three isolated workflows** — each is its own n8n workflow JSON, its own trigger, its own error handler.
- **One mega-workflow** — single workflow with a Switch node at the top branching on trigger type.

The mega-workflow has surface appeal: shared error handling, shared LLM-call logging logic, fewer files to import.

## Decision

Use **three isolated workflows**. The trio share schemas (the `llm_calls` table) but not n8n state.

## Rationale

- **Failure isolation.** When workflow 2 (content brief) breaks at 09:00 because of a malformed RSS feed, workflows 1 and 3 must keep running. One mega-workflow gives a single point of failure.
- **Independent retry policies.** Webhook (workflow 1) is latency-sensitive — 2 retries with short backoff. Cron (workflow 2) is latency-tolerant — could afford longer backoff. IMAP (workflow 3) defers naturally to the next poll on failure.
- **Independent rate limits.** Workflow 2 might spike Anthropic traffic at exactly 09:00 PKT. Isolating means workflow 1's webhook latency is unaffected by the brief job.
- **Independent versioning.** A change to the email-classification prompt doesn't risk breaking the lead-qualification scorer.
- **Cleaner observability.** `llm_calls.workflow_id` is a stable, queryable label. With a mega-workflow, the equivalent would be a branch path string that's brittle to refactors.
- **Portfolio signal.** Three separate workflow JSONs in `workflows/` is more obviously inspectable than one giant JSON. A reviewer can read one and understand it without parsing the others.

## Consequences

- **Positive**: see rationale.
- **Negative**: a small amount of duplication in the error-handler logic. Mitigated by importing a *shared error-handler subflow* (separate workflow set as the "error workflow" on all three).
- **Negative**: three workflow IDs to remember. Documented in `docs/WORKFLOWS.md`.

## Reconsideration triggers

- A genuinely shared dependency emerges (e.g., a 4th workflow that *only* runs after all three succeed). At that point, an orchestration workflow joins the set, but the three remain isolated.
- Cross-workflow state becomes load-bearing — at which point it lives in Postgres, not in n8n.

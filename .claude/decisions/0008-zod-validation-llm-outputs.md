# ADR 0008 — Validation: Zod-equivalent on every LLM output

**Status:** Accepted (Phase 1)
**Date:** 2026-05-14

## Context

Every workflow makes one or more LLM calls and consumes the structured output downstream (Slack message body, Postgres column values, switch-case routing). The classic failure mode of LLM-driven workflows is **silent output drift**:

- The model starts returning an array where it used to return a string.
- A new field appears in the output that downstream nodes ignore.
- A required field becomes optional under certain prompt conditions.

Without validation, these go undetected until a downstream node throws a cryptic "cannot read property of undefined" — or worse, until production data is corrupted.

Three options were considered:

1. **No validation** — trust the prompt; hope for the best.
2. **Loose validation** (existence checks only) — a Function node verifies the top-level keys are present.
3. **Strict schema validation** (Zod-equivalent) — every field's type, range, and enum membership is checked; any drift fails loudly.

## Decision

Use **option 3: strict Zod-equivalent validation** in a Function node after every Anthropic call.

n8n doesn't bundle Zod, but the discipline is replicable in a Function node using plain JavaScript predicate checks (see `.claude/rules/03-workflow-design.md` for the canonical pattern).

## Rationale

- **Fail loud, fail fast.** A `parse_error` row in `llm_calls` is a useful signal. A "score is now sometimes a string" is a 3-hour debugging session.
- **Documents the contract.** The validation function IS the schema contract between the prompt and the rest of the workflow. Anyone reading the workflow JSON understands the expected output without running the workflow.
- **Compounds with observability.** The `status='parse_error'` rows in `llm_calls` let analytics quantify drift rate. Trends matter — drift increasing over a week is the leading indicator of an underlying prompt-or-model-version issue.

## Implementation contract

For each LLM-calling node, the next node is a Function node that:

1. Reads the LLM's parsed JSON output (assumes `response_format: json_object` or equivalent).
2. Checks every required field against its type/range/enum predicate.
3. On any check failure: `throw new Error(...)` with the offending field name + value, which routes to the error workflow.
4. On success: passes the output through unchanged.

The Function node is **stateless** — it does not transform, only validates. Transformation happens in downstream nodes.

## Consequences

- **Positive**: silent drift becomes loud failures, surfaced in Slack alerts and `error_log`.
- **Positive**: each workflow JSON self-documents its expected LLM output.
- **Negative**: a small amount of boilerplate Function-node code per workflow. Mitigated by a `.claude/skills/anthropic-claude-integration/core.md` reference template.

## Reconsideration triggers

- Anthropic's API adds first-class JSON-schema enforcement that's strictly equivalent to the validation we'd write — at which point, simplify by removing the Function node. Until then, validation lives client-side.

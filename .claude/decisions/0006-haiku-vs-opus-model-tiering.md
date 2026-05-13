# ADR 0006 — Model tiering: Haiku 4.5 default, Opus 4.7 for critic only

**Status:** Accepted (Phase 1)
**Date:** 2026-05-14

## Context

Anthropic's current family includes three tiers: Haiku 4.5 (fastest, cheapest), Sonnet 4.6 (balanced), Opus 4.7 (highest capability, slowest, most expensive). Per million tokens, Opus is ~30× more expensive than Haiku.

AutoStream's three workflows have different requirements:

| Workflow | Output shape | Cost-of-error | Latency budget |
|---|---|---|---|
| Lead Qualification | 5-field JSON (score, fit, intent, urgency, rationale) | Low — false positive is "lead reviewed," false negative is "lead missed" | ~2 seconds end-to-end |
| Daily Content Brief | 3-item selection + synthesis paragraph | High — bad brief trains the team to ignore the channel | ~15 seconds (cron, no user waiting) |
| Email Classification | Category enum + confidence | Medium — misrouting wastes time but is recoverable | ~3 seconds |

## Decision

- **Haiku 4.5** for Lead Qualification (workflow 1) and Email Classification (workflow 3).
- **Opus 4.7** for the critic node in Daily Content Brief (workflow 2) only.

## Rationale

- **Haiku is sufficient for structured-output routing.** 5-field JSON with constrained enums is a Haiku problem. Adding Opus capacity here gains marginal accuracy at significant cost — by rule 05, the tier doesn't earn the upgrade.
- **Opus earns its slot for synthesis.** The brief is *the* user-facing artifact of workflow 2. Sub-Opus quality means the team eventually stops reading the channel — a binary failure mode that destroys the workflow's value. The ~10× per-call cost is a small price for a critic that earns the channel its respect.
- **No Sonnet.** The middle tier doesn't earn a slot — every concrete workflow either fits Haiku's capability envelope or warrants Opus's quality.

## Pricing (per million tokens, captured 2026-05)

| Model | Input | Output | Notes |
|---|---|---|---|
| Haiku 4.5 | $1.00 | $5.00 | Default |
| Opus 4.7 | $15.00 | $75.00 | Critic only |

Each `llm_calls` row computes `cost_usd` client-side from these multipliers so the table self-documents the economics.

## Consequences

- **Positive**: predictable cost profile; ~80% of calls hit Haiku (the cheap path).
- **Positive**: clean separation of "routing" vs "judgment" workflows — a useful framing for design reviews.
- **Negative**: brittle to Anthropic pricing changes. Mitigated by recalculating from a single Function node that reads pricing from `.claude/skills/anthropic-claude-integration/reference/model-spec.md`.

## Reconsideration triggers

- Haiku quality drops below the rule-03 schema-pass rate (`status='ok'` < 99%). At that point, upgrade to Sonnet for that workflow, not Opus — preserve the critic-only-Opus discipline.
- Anthropic releases a 4.8 family. Re-tier at that point against fresh benchmarks; don't auto-upgrade.

# Anthropic Model Spec — Tier 3 Reference

Full model catalog with IDs, capabilities, and pricing. Update when Anthropic releases new versions or revises pricing.

## Model IDs (as of 2026-05)

| Family | Latest | Use in AutoStream |
|---|---|---|
| Haiku | `claude-haiku-4-5` | Routing, classification (workflows 1 + 3) |
| Sonnet | `claude-sonnet-4-6` | Reserved — not currently used |
| Opus | `claude-opus-4-7` | Synthesis critic (workflow 2) |

## Pricing per million tokens (2026-05)

| Model | Input | Output | Cached input |
|---|---|---|---|
| `claude-haiku-4-5` | $1.00 | $5.00 | $0.10 (5min) / $0.25 (1h) |
| `claude-sonnet-4-6` | $3.00 | $15.00 | $0.30 (5min) / $0.75 (1h) |
| `claude-opus-4-7` | $15.00 | $75.00 | $1.50 (5min) / $3.75 (1h) |

Cached-input pricing applies to tokens read from the prompt cache (when `cache_control: { type: "ephemeral" }` is set on a system-prompt block). Cache writes are billed at 1.25× the base input rate; cache reads are ~10× cheaper than uncached input.

## Token accounting

Every API response includes:

```json
{
  "usage": {
    "input_tokens": 412,
    "output_tokens": 89,
    "cache_creation_input_tokens": 312,
    "cache_read_input_tokens": 0
  }
}
```

For `cost_usd` calculation purposes, AutoStream uses uncached input pricing as a conservative upper bound — first call writes the cache (1.25× input rate), subsequent calls within 5 min read at 0.1× rate. Over many calls the effective rate trends toward the cached price, but the formula in `core.md` doesn't model this — it's a slight overestimate.

If precise accounting matters at Phase 2 scale, replace the formula with:

```javascript
const cost = (
  usage.cache_creation_input_tokens * (p.input * 1.25) +
  usage.cache_read_input_tokens     * (p.input * 0.10) +
  (usage.input_tokens - usage.cache_creation_input_tokens - usage.cache_read_input_tokens) * p.input +
  usage.output_tokens * p.output
) / 1_000_000;
```

## API version pinning

All HTTP nodes set `anthropic-version: 2023-06-01`. This is the Messages API stable version. Don't bump without re-testing every workflow — newer versions occasionally introduce response-shape changes.

## Rate limits (Tier 4, default)

- Haiku 4.5: 50 RPM, 100K ITPM, 50K OTPM
- Opus 4.7: 50 RPM, 80K ITPM, 16K OTPM

Daily limits per model vary; check the Anthropic Console for current values. AutoStream Phase 1 doesn't approach either limit at demo volume.

## What to recheck when Anthropic releases a new family (4.8, 5.x, etc.)

1. Re-benchmark Haiku-tier prompts (workflows 1 + 3). If the new Haiku is ≥10% better with no cost regression, upgrade `model:` strings.
2. Re-benchmark Opus-tier critic (workflow 2). Same criteria.
3. Update the pricing table in this file + the PRICING map in `core.md`.
4. Update `0006-haiku-vs-opus-model-tiering.md` ADR with the new evaluation.
5. Do NOT auto-update model IDs — each upgrade is a deliberate commit with the benchmark in the message body.

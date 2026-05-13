# Rule 05 — Cost Control

AutoStream Phase 1 runs on **zero cash spending**. All infrastructure and APIs come from free tiers or existing Anthropic credits.

## Free-tier budgets

| Service | Free tier | AutoStream usage at demo volume |
|---|---|---|
| Railway | $5 trial credit, 30 days | n8n + Postgres → ~$3 for the window |
| Anthropic | Existing prepaid credits | Haiku for routing, Opus for critic only |
| Supabase | 500MB DB, 50k MAU, 2GB egress | `llm_calls` ~10k rows = ~5MB |
| Slack | Free workspace tier | unlimited incoming webhooks |
| GitHub | Free public repo | source + Issues + Actions (Phase 2) |

If any of these threatens to exceed free tier, **stop and document it as a Phase 2 cost** rather than upgrading silently.

## Anthropic model tiering

Default to Haiku 4.5 (`claude-haiku-4-5`). Use Opus 4.7 (`claude-opus-4-7`) only when the *quality of the output materially affects downstream behavior*:

| Use case | Model | Why |
|---|---|---|
| Lead-qualification scoring | Haiku 4.5 | Routing decision; speed matters; Haiku is sufficient |
| Email categorization | Haiku 4.5 | 5-way classification; Haiku is sufficient |
| Daily content brief critic | **Opus 4.7** | Synthesis quality compounds — a bad brief trains the team to ignore the channel |

This rule is enforced socially (in code review of new workflow JSONs) and surfaced quantitatively in `llm_calls.cost_usd` aggregates.

## Cost-monitoring queries

Run periodically (or wire into a daily cron):

```sql
-- Per-workflow monthly spend
select workflow_id,
       sum(cost_usd) as month_to_date_usd,
       count(*) as call_count,
       avg(duration_ms)::int as avg_latency_ms
  from llm_calls
 where created_at >= date_trunc('month', now())
 group by workflow_id
 order by month_to_date_usd desc;

-- Outliers (single calls > 10x average for the workflow)
with avg_cost as (
  select workflow_id, avg(cost_usd) as avg_usd from llm_calls
   where created_at >= now() - interval '7 days'
   group by workflow_id
)
select c.id, c.workflow_id, c.cost_usd, c.created_at
  from llm_calls c
  join avg_cost a using (workflow_id)
 where c.cost_usd > 10 * a.avg_usd
   and c.created_at >= now() - interval '24 hours'
 order by c.cost_usd desc;
```

## Cost-failure modes to monitor

| Failure | Detection | Action |
|---|---|---|
| Unbounded retry burns Anthropic credits | `llm_calls` row count spike | Check `error_log` — there's a retry loop somewhere. Rule 03 violation. |
| Opus accidentally used for routing | `model='claude-opus-4-7'` in workflow 1 or 3 rows | Audit the workflow JSON; revert to Haiku. |
| Large prompts uncached | `prompt_tokens` rising while caller is unchanged | Set `cache_control: { type: 'ephemeral' }` on the system prompt in the HTTP node. |
| RSS feed dumps backlogged content as "new" | content-brief workflow ingests 200 items in one run | Add dedup horizon (already in workflow 2 — 7-day GUID lookback). |

## When this rule changes

Phase 1 — current rule applies, zero-cash.

Phase 2 — relaxes to "predictable monthly cost ≤ $50" once production-hardening adds Redis, multiple workers, monitoring.

Phase 3 — relaxes to "unit economics positive on Anthropic spend" once BYOK is in place (each tenant pays their own LLM bill).

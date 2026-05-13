# Scaling

What changes when AutoStream moves from "portfolio demo" volume (1k webhooks/mo, 30 briefs/mo, 3k emails/mo) to ~100× volume.

The current single-instance architecture handles the demo volume comfortably. Below are the exact changes — and their thresholds — that move AutoStream into production-grade territory.

---

## When to scale (signals from `llm_calls` and `workflow_runs`)

| Signal | Threshold | Action |
|---|---|---|
| `workflow_runs.duration_ms` p99 > 30s on Lead Qualification | sustained 24h | Move n8n to **queue mode** with a separate worker container |
| Anthropic 429 rate ≥ 1% of calls | weekly | Add per-workflow rate limiter (semaphore in Function node or Redis token bucket) |
| Postgres CPU > 70% sustained | weekly | Move internal n8n DB off the n8n container; tune pool size |
| Single workflow > 100k runs/day | sustained | Shard observability writes (separate `llm_calls_archive` partition by month) |

---

## Phase A: Queue mode

By default n8n runs all executions in the main process. Under load, slow workflows block fast ones. Switch to queue mode:

```yaml
# docker-compose.yml diff (high level)
services:
  redis:
    image: redis:7-alpine
  n8n:
    environment:
      EXECUTIONS_MODE: queue
      QUEUE_BULL_REDIS_HOST: redis
  n8n-worker:
    image: n8nio/n8n:1.71.3
    command: n8n worker
    deploy:
      replicas: 3
    environment:
      EXECUTIONS_MODE: queue
      QUEUE_BULL_REDIS_HOST: redis
      # ... same DB/encryption-key env as main
```

Cost: +1 Redis service, +N worker replicas. Benefit: webhook → Slack latency stays flat as volume grows; the 09:00 cron brief no longer blocks the 09:00 emails.

**Caveat**: workflows that mutate IMAP state (workflow 3) must run on exactly one worker at a time to avoid race conditions on `mark as Seen`. Constrain via a Bull queue with concurrency 1 for that workflow ID.

---

## Phase B: Postgres separation

The default `docker-compose.yml` co-locates n8n with its internal Postgres. Under load:

- n8n's binary data + execution logs grow fast
- LLM-call observability writes to **Supabase** (separate Postgres) so observability isn't affected
- But n8n's *own* DB will become the bottleneck on writes (execution data persistence)

Action: move n8n's DB to a managed instance (Supabase has a second project, or Railway's Postgres plugin). Set `EXECUTIONS_DATA_PRUNE=true` + `EXECUTIONS_DATA_MAX_AGE=168` (7 days) to keep the table small.

---

## Phase C: Rate limiting

When Anthropic 429s start appearing in `llm_calls.status='api_error'`:

1. **Per-workflow semaphore** (cheap, in-process): a Function node holds a counter in `$workflow.staticData` and blocks above the limit.
2. **Cross-worker semaphore** (when queue mode is on): use a Redis-based token bucket — one bucket per model (Haiku and Opus have separate Tier 4 limits).
3. **Backoff with jitter**: not just retry-on-429, but retry with `2^attempt * (1 + random(0, 0.3))` jitter so 100 concurrent workflows don't all retry on the same wall-clock tick.

---

## Phase D: Observability sharding

At 100k+ rows/day in `llm_calls`:

- Partition by month: `create table llm_calls partition of llm_calls_root for values from ('2026-06-01') to ('2026-07-01')`.
- Drop indexes that don't earn their write cost. Keep `(workflow_id, created_at desc)` and `status` (partial). Drop anything over `output->>'score'` etc. — query on the fly when needed.
- Move analytics queries to a separate read-replica (Supabase read replicas, or a daily logical-replication dump into BigQuery / DuckDB for ad-hoc work).

---

## What stays the same

- **Three isolated workflows**. The architecture decision (ADR 0002) holds at 100×; isolation pays off more under load, not less.
- **Zod-equivalent validation on every LLM output**. Validation cost is negligible vs the LLM call itself.
- **Bounded retry**. The "max 2 attempts" rule applies at every scale — what changes is what happens *after* the second failure (more sophisticated rate limiting, dead-letter queue, etc.).
- **Single-author git discipline**. Doesn't change with team size — only the human signing the commits would change.

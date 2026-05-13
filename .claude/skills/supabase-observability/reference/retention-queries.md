# Retention + Index Tuning — Tier 3 Reference

When `llm_calls` row count exceeds ~100k or Supabase storage approaches 80% of free-tier cap, switch on retention. Until then, keep all rows.

## Retention strategy

Two options:

1. **Soft delete** — add `archived_at timestamptz`; nightly job sets `archived_at = now()` on rows older than 90 days; queries filter `where archived_at is null`. Keeps history queryable but pays storage cost.

2. **Hard delete** — nightly job deletes rows older than 90 days. Free-tier-friendly; loses history.

For Phase 1: do neither. For Phase 2: hard delete after 30 days (acceptable since `error_log` retains the failure summary) and roll up daily aggregates into `llm_calls_daily`:

```sql
create table llm_calls_daily (
  day             date not null,
  workflow_id     text not null,
  model           text not null,
  call_count      int  not null,
  prompt_tokens   bigint not null,
  output_tokens   bigint not null,
  cost_usd        numeric(10, 2) not null,
  ok_count        int not null,
  parse_err_count int not null,
  api_err_count   int not null,
  primary key (day, workflow_id, model)
);
```

Nightly roll-up:
```sql
insert into llm_calls_daily (day, workflow_id, model, call_count, prompt_tokens, output_tokens, cost_usd, ok_count, parse_err_count, api_err_count)
select date(created_at), workflow_id, model,
       count(*), sum(prompt_tokens), sum(output_tokens), sum(cost_usd),
       count(*) filter (where status = 'ok'),
       count(*) filter (where status = 'parse_error'),
       count(*) filter (where status = 'api_error')
  from llm_calls
 where created_at >= current_date - interval '1 day'
   and created_at <  current_date
 group by date(created_at), workflow_id, model
on conflict (day, workflow_id, model) do update set
  call_count = excluded.call_count,
  prompt_tokens = excluded.prompt_tokens,
  output_tokens = excluded.output_tokens,
  cost_usd = excluded.cost_usd,
  ok_count = excluded.ok_count,
  parse_err_count = excluded.parse_err_count,
  api_err_count = excluded.api_err_count;
```

## Index tuning

The default indexes from migration 0001 are sufficient for Phase 1 + Phase 2:

```sql
create index on llm_calls (workflow_id, created_at desc);
create index on llm_calls (status) where status != 'ok';   -- partial
create index on workflow_runs (workflow_id, started_at desc);
create index on error_log (workflow_id, created_at desc);
```

Don't add more without measurement. Common temptations to resist:

- `(workflow_id, status)` — covered by composite + partial above
- `(model)` — too low-cardinality to be useful as a sole index
- GIN on `output` JSONB — only useful if you regularly query specific paths; ad-hoc EXPLAIN-tune before committing the index

## Partition by month (Phase 3 multi-tenant)

When daily inserts exceed ~10k rows per workflow, partition `llm_calls`:

```sql
create table llm_calls_root (
  -- same columns as llm_calls
) partition by range (created_at);

create table llm_calls_2026_06 partition of llm_calls_root
  for values from ('2026-06-01') to ('2026-07-01');
create table llm_calls_2026_07 partition of llm_calls_root
  for values from ('2026-07-01') to ('2026-08-01');
-- ... pre-create 12 months ahead
```

Drop old partitions cheaply: `drop table llm_calls_2026_06` deletes the month in O(1).

## Backup discipline

Supabase free-tier provides 7-day point-in-time recovery automatically. For longer retention:

- Daily `pg_dump` of `llm_calls_daily` (post-aggregation) to local archive. Small file — ships in `~/Documents/projects/autostream-archive/`.
- Never `pg_dump` raw `llm_calls` for archive — too noisy + may contain redacted-but-still-sensitive fields.

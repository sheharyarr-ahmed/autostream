# Supabase Observability — Core

Hot-path: schema, insert payloads, common queries.

## Schema (recap from migration 0001)

```sql
llm_calls       (id, workflow_id, workflow_run_id, model, prompt_tokens, output_tokens,
                 duration_ms, cost_usd, input, output, status, created_at)
workflow_runs   (id, workflow_id, status, duration_ms, started_at, ended_at, meta)
error_log       (id, workflow_id, workflow_run_id, kind, error_message, context, created_at)
```

Status enums:
- `llm_calls.status`: `ok` | `parse_error` | `api_error`
- `workflow_runs.status`: `ok` | `error` | `skipped_empty`

## Insert from n8n HTTP node

### `llm_calls` insert
```http
POST {{ $env.SUPABASE_URL }}/rest/v1/llm_calls
apikey: {{ $env.SUPABASE_SERVICE_ROLE_KEY }}
Authorization: Bearer {{ $env.SUPABASE_SERVICE_ROLE_KEY }}
Content-Type: application/json
Prefer: return=minimal

{
  "workflow_id": "lead-qualification",
  "workflow_run_id": "{{ $execution.id }}",
  "model": "{{ $json.model }}",
  "prompt_tokens": {{ $json.usage.input_tokens }},
  "output_tokens": {{ $json.usage.output_tokens }},
  "duration_ms":   {{ $json.duration_ms }},
  "cost_usd":      {{ $json.cost_usd }},
  "input":  {{ JSON.stringify($json.input) }},
  "output": {{ JSON.stringify($json.parsed) }},
  "status": "ok"
}
```

`Prefer: return=minimal` makes the response empty (no body returned), saving ingress.

### `workflow_runs` insert
At workflow end:

```json
{
  "id": "{{ $execution.id }}",
  "workflow_id": "lead-qualification",
  "status": "ok",
  "duration_ms": {{ Date.now() - $execution.startedAt }},
  "started_at": "{{ new Date($execution.startedAt).toISOString() }}",
  "ended_at":   "{{ new Date().toISOString() }}",
  "meta": {}
}
```

### `error_log` insert (from error workflow)

```json
{
  "workflow_id": "{{ $('Failed Workflow').params.workflow_id }}",
  "workflow_run_id": "{{ $('Failed Workflow').params.execution_id }}",
  "kind": "anthropic_429",
  "error_message": "{{ $json.error.message }}",
  "context": { "node": "{{ $json.error.node }}", "attempt": {{ $json.error.attempt }} }
}
```

## Common queries

```sql
-- Last 10 failures across all workflows
select workflow_id, kind, error_message, created_at
  from error_log
 order by created_at desc
 limit 10;

-- Token spend by model this month
select model, sum(prompt_tokens) as in_tok, sum(output_tokens) as out_tok, sum(cost_usd) as usd
  from llm_calls
 where created_at >= date_trunc('month', now())
 group by model;

-- Slow workflow runs (p99 last 24h)
select workflow_id,
       percentile_cont(0.99) within group (order by duration_ms) as p99_ms,
       count(*) as runs
  from workflow_runs
 where started_at >= now() - interval '24 hours'
 group by workflow_id;

-- Parse-error drill-down
select created_at, output -> 'raw' as offending_output
  from llm_calls
 where workflow_id = 'lead-qualification'
   and status = 'parse_error'
 order by created_at desc
 limit 20;
```

## Don'ts

- **Don't query from inside a workflow's hot path.** Reading from `llm_calls` to influence the next call introduces feedback that confuses observability. Workflows write only.
- **Don't add foreign keys.** n8n executes nodes in parallel where it can; FK violations would cause spurious failures.
- **Don't truncate `llm_calls`** — retention is a Phase 2+ concern (`reference/retention-queries.md`); Phase 1 has plenty of headroom.

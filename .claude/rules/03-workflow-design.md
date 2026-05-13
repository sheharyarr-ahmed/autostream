# Rule 03 — Workflow Design

Every n8n workflow in AutoStream must follow these four constraints. No exceptions.

## 1. Bounded retry — max 2 attempts

Every external call (HTTP node hitting Anthropic / Supabase / Slack, RSS feed read, IMAP fetch) has retry set to **2 attempts** with exponential backoff. After the second failure:

- Route to the shared error workflow.
- Insert a row into `error_log` with `kind`, `workflow_id`, `error_message`, `attempt_count=2`.
- Post to `#autostream-errors`.

**Never unbounded retry.** A loop that retries until success will exhaust an API quota in minutes and bill you for the failures.

## 2. Zod-equivalent validation on every LLM output

n8n doesn't have native Zod, but you can replicate the discipline in a Function node:

```javascript
// Function node — strict schema for lead-qualification output
const schema = {
  score:     v => typeof v === 'number' && v >= 0 && v <= 100,
  fit:       v => ['low', 'medium', 'high'].includes(v),
  intent:    v => ['research', 'evaluate', 'buy'].includes(v),
  urgency:   v => ['low', 'medium', 'high'].includes(v),
  rationale: v => typeof v === 'string' && v.length > 0 && v.length < 500,
};

const output = $json.output;
for (const [field, check] of Object.entries(schema)) {
  if (!check(output[field])) {
    throw new Error(`schema validation failed: field=${field} value=${JSON.stringify(output[field])}`);
  }
}
return $input.all();
```

The thrown error routes to the error workflow, which inserts an `llm_calls` row with `status='parse_error'`. Don't catch and continue with bad data.

## 3. Log every LLM call to Supabase

Every Anthropic HTTP node is followed by a Supabase HTTP node that inserts into `llm_calls`. **Always.** Even when the LLM call failed. Even when the workflow ends early.

Required columns:

| Column | Source |
|---|---|
| `workflow_id` | hardcoded constant per workflow |
| `workflow_run_id` | `{{$execution.id}}` |
| `model` | `claude-haiku-4-5` or `claude-opus-4-7` |
| `prompt_tokens` | response `usage.input_tokens` |
| `output_tokens` | response `usage.output_tokens` |
| `duration_ms` | `Date.now() - $node["Anthropic"].context.startedAt` |
| `cost_usd` | calculated client-side from token counts × model pricing |
| `input` | redacted (no PII, no secrets) |
| `output` | the parsed/validated object, or raw text if parse failed |
| `status` | `'ok'`, `'parse_error'`, or `'api_error'` |

## 4. Alert on every failure

The shared error workflow:

1. Inserts a row into `error_log`.
2. Posts a Slack Block Kit message to `#autostream-errors` with `workflow_id`, `execution_id`, `kind`, `error_message`, link to the n8n execution page.

No silent failures. No "we'll catch it in the metrics dashboard next week." If a workflow fails, someone is paged within seconds.

---

## Self-check before importing a new workflow

```
[ ] All HTTP / RSS / IMAP nodes have retry = 2, backoff = exponential
[ ] LLM output goes through a Function node that validates the schema
[ ] Both the success branch AND the error branch insert to llm_calls
[ ] Error workflow is wired up (workflow settings → error workflow)
[ ] Workflow ID is a stable string (won't change when the workflow is renamed)
[ ] No credentials hardcoded — all secrets come from $env or credentials
```

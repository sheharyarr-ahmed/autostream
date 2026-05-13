# Anthropic Integration — Core

Hot-path templates for the HTTP node body and the validation Function node.

## HTTP request body template

```json
{
  "model": "claude-haiku-4-5",
  "max_tokens": 1024,
  "system": [
    {
      "type": "text",
      "text": "You are a B2B-SaaS lead qualifier. Score the inbound lead on fit (low|medium|high), intent (research|evaluate|buy), and urgency (low|medium|high), and produce a 1-2 sentence rationale. Output JSON only, matching the schema { score: 0-100, fit, intent, urgency, rationale }. No prose, no markdown fence.",
      "cache_control": { "type": "ephemeral" }
    }
  ],
  "messages": [
    { "role": "user", "content": "{{$json.payload}}" }
  ]
}
```

`cache_control: { type: "ephemeral" }` caches the system prompt for ~5 min, so the boilerplate only bills once per call burst.

## Validation Function node (Zod-equivalent, per rule 03)

```javascript
// Parse Claude's response (the content is a string; we expect JSON)
const responseText = $json.content?.[0]?.text;
let output;
try {
  output = JSON.parse(responseText);
} catch (e) {
  throw new Error(`Claude returned non-JSON: ${responseText?.slice(0, 200)}`);
}

// Strict schema check — every field, every type, every enum
const schema = {
  score:     v => typeof v === 'number' && Number.isInteger(v) && v >= 0 && v <= 100,
  fit:       v => ['low', 'medium', 'high'].includes(v),
  intent:    v => ['research', 'evaluate', 'buy'].includes(v),
  urgency:   v => ['low', 'medium', 'high'].includes(v),
  rationale: v => typeof v === 'string' && v.length >= 10 && v.length <= 500,
};

for (const [field, check] of Object.entries(schema)) {
  if (!check(output[field])) {
    throw new Error(`schema mismatch: field=${field} value=${JSON.stringify(output[field])}`);
  }
}

// Pass through with parsed output attached
return [{
  json: {
    ...$input.first().json,
    parsed: output,
    usage: $json.usage,
    model: $json.model,
  }
}];
```

## Cost calculation (client-side)

Pricing per million tokens (kept in `reference/model-spec.md` for updates):

```javascript
const PRICING = {
  'claude-haiku-4-5': { input: 1.00, output: 5.00 },
  'claude-opus-4-7':  { input: 15.00, output: 75.00 },
};
const p = PRICING[$json.model];
const cost = (
  $json.usage.input_tokens  * p.input  +
  $json.usage.output_tokens * p.output
) / 1_000_000;
return [{ json: { ...$input.first().json, cost_usd: cost } }];
```

## llm_calls insert payload

```json
{
  "workflow_id": "lead-qualification",
  "workflow_run_id": "={{$execution.id}}",
  "model": "={{$json.model}}",
  "prompt_tokens":  "={{$json.usage.input_tokens}}",
  "output_tokens":  "={{$json.usage.output_tokens}}",
  "duration_ms":    "={{Math.round(($node['validate'].context.endedAt || Date.now()) - $node['Anthropic'].context.startedAt)}}",
  "cost_usd":       "={{$json.cost_usd}}",
  "input":          "={{$node['redact'].json}}",
  "output":         "={{$json.parsed}}",
  "status":         "ok"
}
```

For parse-error and api-error paths, the same shape with `status` set accordingly and `output` containing the raw (unparsed) Claude response or error message.

## What goes in the system prompt vs the user message

- **System (cached)**: role, output schema description, formatting constraints, hard rules ("never include PII in the rationale field").
- **User (per-call)**: the specific input data (email body, lead form fields, RSS items).

A common mistake: putting the schema description in the user message. This breaks caching and re-bills the boilerplate every call.

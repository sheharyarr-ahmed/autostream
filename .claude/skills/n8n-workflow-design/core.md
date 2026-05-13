# n8n Workflow Design — Core

Hot-path knowledge for authoring AutoStream workflows. Always loaded when this skill is invoked.

## Trigger nodes

### Webhook
```json
{
  "parameters": {
    "httpMethod": "POST",
    "path": "lead",
    "responseMode": "lastNode",
    "options": { "rawBody": true }
  },
  "type": "n8n-nodes-base.webhook"
}
```

`rawBody: true` is critical — HMAC verification needs the unparsed body bytes.

### Schedule Trigger (cron)
```json
{
  "parameters": {
    "rule": {
      "interval": [{ "field": "cronExpression", "expression": "0 9 * * *" }]
    },
    "timezone": "={{$env.TIMEZONE}}"
  },
  "type": "n8n-nodes-base.scheduleTrigger"
}
```

### Email Trigger (IMAP)
```json
{
  "parameters": {
    "mailbox": "INBOX",
    "downloadAttachments": false,
    "options": {
      "customEmailConfig": "UNSEEN",
      "forceReconnect": 30
    },
    "postProcessAction": "nothing"
  },
  "type": "n8n-nodes-base.emailReadImap"
}
```

`postProcessAction: "nothing"` — we mark-as-seen explicitly downstream after success.

## Retry pattern (rule 03)

Every HTTP / RSS / IMAP node must include:

```json
"retryOnFail": true,
"maxTries": 2,
"waitBetweenTries": 1000
```

For exponential backoff (n8n doesn't expose multiplier), use a Wait node between attempts only when a single workflow legitimately needs > 2 attempts (it shouldn't, per rule 03).

## HMAC verification (Function node, first child of Webhook)

```javascript
const crypto = require('crypto');
const secret = $env.WEBHOOK_HMAC_SECRET;
const signature = $headers['x-signature'];
const body = JSON.stringify($json);
const expected = crypto.createHmac('sha256', secret).update(body).digest('hex');

if (!signature || !crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) {
  throw new Error('Invalid HMAC signature');
}
return $input.all();
```

## Anthropic HTTP node

```json
{
  "parameters": {
    "url": "https://api.anthropic.com/v1/messages",
    "method": "POST",
    "sendHeaders": true,
    "headerParameters": {
      "parameters": [
        { "name": "x-api-key", "value": "={{$env.ANTHROPIC_API_KEY}}" },
        { "name": "anthropic-version", "value": "2023-06-01" },
        { "name": "content-type", "value": "application/json" }
      ]
    },
    "sendBody": true,
    "bodyParameters": { ... },
    "options": { "timeout": 30000 }
  },
  "type": "n8n-nodes-base.httpRequest",
  "retryOnFail": true,
  "maxTries": 2,
  "waitBetweenTries": 1000
}
```

## Supabase insert (HTTP Request)

```json
{
  "parameters": {
    "url": "={{$env.SUPABASE_URL}}/rest/v1/llm_calls",
    "method": "POST",
    "sendHeaders": true,
    "headerParameters": {
      "parameters": [
        { "name": "apikey", "value": "={{$env.SUPABASE_SERVICE_ROLE_KEY}}" },
        { "name": "Authorization", "value": "=Bearer {{$env.SUPABASE_SERVICE_ROLE_KEY}}" },
        { "name": "content-type", "value": "application/json" },
        { "name": "Prefer", "value": "return=minimal" }
      ]
    },
    "sendBody": true,
    "bodyContentType": "json",
    "jsonBody": "={ ... }"
  }
}
```

## Error workflow wiring

Workflow Settings → "Error Workflow" dropdown → point at the shared error-handler workflow (which itself takes the failing execution's metadata + error message and posts to Slack + inserts `error_log` row).

## Expression cheatsheet

- `{{$json.field}}` — current node input
- `{{$node["NodeName"].json.field}}` — earlier node by name
- `{{$env.KEY}}` — environment variable
- `{{$execution.id}}` — current execution UUID (use for `workflow_run_id` in `llm_calls`)
- `{{$workflow.id}}` — workflow ID (less useful — prefer hardcoded stable string for `workflow_id` column)
- `{{$now}}` — ISO timestamp
- `{{ $json.text || $json.html.replace(/<[^>]+>/g, '') }}` — strip HTML fallback

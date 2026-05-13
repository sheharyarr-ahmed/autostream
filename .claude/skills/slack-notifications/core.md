# Slack Notifications — Core

Block Kit templates for the four kinds of message AutoStream sends.

## 1. Qualified-lead alert (workflow 1)

```json
{
  "blocks": [
    {
      "type": "header",
      "text": { "type": "plain_text", "text": "🎯 Qualified lead — score {{$json.parsed.score}}" }
    },
    {
      "type": "section",
      "fields": [
        { "type": "mrkdwn", "text": "*Email*\n{{$json.email}}" },
        { "type": "mrkdwn", "text": "*Intent*\n{{$json.parsed.intent}}" },
        { "type": "mrkdwn", "text": "*Fit*\n{{$json.parsed.fit}}" },
        { "type": "mrkdwn", "text": "*Urgency*\n{{$json.parsed.urgency}}" }
      ]
    },
    {
      "type": "section",
      "text": { "type": "mrkdwn", "text": "*Rationale*\n{{$json.parsed.rationale}}" }
    },
    {
      "type": "context",
      "elements": [
        { "type": "mrkdwn", "text": "workflow_run_id: `{{$execution.id}}`" }
      ]
    }
  ]
}
```

## 2. Daily content brief (workflow 2)

```json
{
  "blocks": [
    {
      "type": "header",
      "text": { "type": "plain_text", "text": "📰 Daily brief — {{ DateTime.now().setZone($env.TIMEZONE).toFormat('cccc, LLL d') }}" }
    },
    {
      "type": "section",
      "text": { "type": "mrkdwn", "text": "{{$json.parsed.synthesis}}" }
    },
    { "type": "divider" },
    {
      "type": "section",
      "text": { "type": "mrkdwn", "text": "*Top picks*" }
    }
    // ... then one section per item with title + source + why_it_matters
  ]
}
```

Items appended dynamically — use a Function node that maps `$json.parsed.items` to one section block each, then merge into the parent `blocks` array.

## 3. Email-classification routing (workflow 3)

Per-category channel — same template, different webhook URL or different `channel` field.

```json
{
  "blocks": [
    {
      "type": "section",
      "text": { "type": "mrkdwn", "text": "*[{{$json.parsed.urgency | upper}}] {{$json.subject}}*\nFrom: `{{$json.from}}`\n\n{{$json.parsed.summary}}" }
    },
    {
      "type": "context",
      "elements": [
        { "type": "mrkdwn", "text": "category: {{$json.parsed.category}} · confidence: {{$json.parsed.confidence}}" }
      ]
    }
  ]
}
```

## 4. Error alert (error workflow → #autostream-errors)

```json
{
  "blocks": [
    {
      "type": "header",
      "text": { "type": "plain_text", "text": "🚨 {{$json.workflow_id}} failed" }
    },
    {
      "type": "section",
      "fields": [
        { "type": "mrkdwn", "text": "*Kind*\n{{$json.kind}}" },
        { "type": "mrkdwn", "text": "*Node*\n{{$json.error.node || 'unknown'}}" }
      ]
    },
    {
      "type": "section",
      "text": { "type": "mrkdwn", "text": "```{{$json.error.message}}```" }
    },
    {
      "type": "actions",
      "elements": [
        {
          "type": "button",
          "text": { "type": "plain_text", "text": "View execution" },
          "url": "{{$env.N8N_PUBLIC_URL}}/workflow/{{$json.workflow_id}}/executions/{{$json.execution_id}}"
        }
      ]
    }
  ]
}
```

## Rate-limit awareness

- ~1 message/sec per webhook URL.
- ~10/sec across all webhooks in a workspace.
- For workflow 2 (single message per cron tick) and 3 (per-email throttle ≤ 1/sec realistic), this is never an issue.
- If you ever consider fanning out (one Slack message per qualified lead in a burst), batch instead — one message listing N leads.

## Posting via HTTP Request

```json
{
  "parameters": {
    "url": "={{$env.SLACK_WEBHOOK_URL}}",
    "method": "POST",
    "sendBody": true,
    "bodyContentType": "json",
    "jsonBody": "={{JSON.stringify($json.slack_blocks)}}"
  },
  "type": "n8n-nodes-base.httpRequest",
  "retryOnFail": true,
  "maxTries": 2,
  "waitBetweenTries": 1000
}
```

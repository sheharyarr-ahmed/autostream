# n8n Node Catalog — Tier 3 Reference

Edge cases, less-common nodes, and gotchas. Load on demand only — most workflow work needs `core.md` alone.

## RSS Feed Read

`n8n-nodes-base.rssFeedRead` — fetches and parses one feed URL per invocation.

```json
{
  "parameters": {
    "url": "https://example.com/feed.xml",
    "options": {
      "ignoreSSL": false
    }
  }
}
```

To iterate over multiple feeds: precede with a Code node that splits `$env.RSS_FEEDS` (comma-separated URLs) into items, then Split In Batches.

**Gotchas:**
- Atom vs RSS 2.0 vs RSS 1.0 — n8n's parser handles all three, but field names differ across formats. Normalize in a subsequent Function node:
  ```javascript
  const items = $input.all().map(item => ({
    json: {
      guid: item.json.guid || item.json.id || item.json.link,
      title: item.json.title,
      link: item.json.link,
      pubDate: item.json.pubDate || item.json.isoDate || item.json.published,
      source: $node.parameter.url
    }
  }));
  return items;
  ```
- Broken / malformed feeds throw — bounded retry covers transient failures; permanent failures route to error workflow per workflow 2's "skip-feed-continue-brief" pattern.

## Switch

`n8n-nodes-base.switch` — branch on a value to N output paths.

Use Switch when ≥3 branches; use IF for binary. Switch is cleaner for email-category routing (5 categories).

```json
{
  "parameters": {
    "rules": {
      "rules": [
        { "value2": "sales",      "operation": "equal", "output": 0 },
        { "value2": "support",    "operation": "equal", "output": 1 },
        { "value2": "recruiting", "operation": "equal", "output": 2 },
        { "value2": "billing",    "operation": "equal", "output": 3 }
      ]
    },
    "value1": "={{$json.output.category}}",
    "fallbackOutput": 4
  }
}
```

## Merge

`n8n-nodes-base.merge` — combine outputs from multiple branches.

Modes:
- **append** — concat all input items (default for fanning back in)
- **multiplex** — cartesian product (rarely useful here)
- **combineByPosition** — pairs items by index
- **combineByKey** — joins items by a shared key field (most useful for content brief: merge enriched-with-Claude items with original feed metadata)

## Function vs Code

- `Function` — runs once per input item; `$json` is current item
- `Code` — runs once per workflow; `items` is the full input array

For per-item validation (Zod-equivalent), use Function. For batch operations (dedup, sort, merge), use Code.

## Wait

`n8n-nodes-base.wait` — pause workflow for N seconds or until a timestamp.

Avoid in AutoStream workflows except in the error workflow's "alert throttle" — don't pile 100 identical errors into Slack within 1 minute. Wait 60s between identical errors using `$workflow.staticData` as a cooldown map.

## Code node — pinning Node.js features

If a Function node needs a specific Node version's feature (e.g., structured clone), pin in the workflow's Settings → "Execution Order" → "Run once for all items" mode, since per-item mode has stricter sandboxing.

## n8n Expression vs JavaScript

Inside `{{ }}` you write JavaScript with access to:
- `$json`, `$node`, `$env`, `$execution`, `$workflow`
- `DateTime` (Luxon)
- `$jmespath()` for JSON path queries

You do NOT have access to:
- `require()` (use Function/Code node for that)
- Native fetch (use HTTP Request node)
- File system (use Read/Write Binary File nodes)

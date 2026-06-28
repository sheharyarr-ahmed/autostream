# Workflows

Per-workflow spec for the three AutoStream workflows. Each section documents trigger, node graph, expressions, retry policy, error path, and the Supabase rows produced.

---

## 1. Lead Qualification — `workflows/01-lead-qualification.json`

### Purpose
Score inbound leads against fit + intent + urgency. Alert sales only on high-signal leads. Always persist the call for retroactive analysis.

### Trigger
`POST /webhook/lead` — HMAC-SHA256 signed, secret in `WEBHOOK_HMAC_SECRET`.

Signature header: `X-Signature` (hex-encoded HMAC of the raw request body).

### Node graph

```
Webhook (HMAC-verified, timingSafeEqual)
  → Anthropic Claude (Haiku 4.5)
  → Zod-equivalent validation (score + fit + intent + urgency)
  → Supabase Insert → llm_calls       (runs on EVERY execution)
  → Supabase Insert → workflow_runs
  ↘ IF score ≥ 70
      → Slack (post to #autostream-alerts)
  (error workflow on any failure → Slack #autostream-errors + error_log)
```

### Expressions
- HMAC verify: `crypto.createHmac('sha256', $env.WEBHOOK_HMAC_SECRET).update(JSON.stringify($json.body)).digest('hex')` — compared with `$json.headers['x-signature']` via `crypto.timingSafeEqual` (buffers must match length first)
- Score threshold: `parseInt($json.output.score, 10) >= 70`
- Cost calc: `($json.usage.input_tokens * 1.00 + $json.usage.output_tokens * 5.00) / 1000000` (Haiku 4.5 pricing per million)

### Retry policy
Max **2 attempts** (`retryOnFail: true, maxTries: 2, waitBetweenTries: 1000`) on the Anthropic HTTP node, both Supabase nodes, and the Slack node. After 2 failures on any node, the error workflow fires.

### Output schema (Zod-equivalent — see `.claude/skills/anthropic-claude-integration/core.md`)
```json
{
  "score": 0-100,
  "fit": "low|medium|high",
  "intent": "research|evaluate|buy",
  "urgency": "low|medium|high",
  "rationale": "1-2 sentences"
}
```

### Failure modes
| Failure | Detection | Action |
|---|---|---|
| HMAC mismatch | `IF` node compares header vs computed | 401 response, no Claude call |
| Schema parse error | Zod-equivalent validation in Function node | Log to `llm_calls` with `status=parse_error`, alert Slack |
| Anthropic 429 | HTTP node retry policy | Retry once after 4s; second failure → error workflow |
| Slack 429 | Slack node | Drop the alert; the row still lands in `llm_calls` for retroactive review |

---

## 2. Daily Content Brief — `workflows/02-daily-content-brief.json`

### Purpose
Replace the daily ritual of reading 50 RSS feeds with one Slack post containing the three items that matter, distilled.

### Trigger
Cron node — `0 9 * * *` in `Asia/Karachi` (configurable via `TIMEZONE` env).

### Node graph

```
Cron (09:00 PKT)
  → Loop over RSS_FEEDS env (comma-separated URLs)
    → RSS Feed Read node
    → Filter (item.pubDate within last 24h)
    → Dedup against content_briefs.guid (last 7 days)
  → Merge → flatten + sort by pubDate desc
  → HTTP Request → Anthropic Claude (Opus 4.7, critic role)
  → Zod-equivalent validation
  → Slack (post to #daily-brief with top 3 items + 1-paragraph synthesis)
  → Supabase Insert → llm_calls
  → Supabase Insert → content_briefs (for dedup horizon)
  (error workflow → Slack + error_log)
```

### Why Opus for this one?
Synthesis quality compounds — a weak brief is worse than no brief because it trains the team to ignore the channel. Opus 4.7 in critic role (rejects items that don't earn the slot, summarizes the remainder) is worth the ~10× cost per call. See ADR 0006.

### Retry policy
Max **2 attempts** on each RSS read + on the Opus call. Failed feed: skip with a warning logged to `error_log`; brief still ships with the feeds that succeeded.

### Output schema
```json
{
  "items": [
    { "title": "...", "url": "...", "source": "...", "why_it_matters": "1 sentence" }
  ],
  "synthesis": "150-200 word paragraph"
}
```

### Failure modes
| Failure | Detection | Action |
|---|---|---|
| Single RSS feed down | per-iteration error in Loop | Skip + `error_log`; brief continues with remaining feeds |
| All feeds empty (last 24h) | Item count 0 after dedup | Skip brief; log to `workflow_runs` with `status='skipped_empty'`; no Slack post |
| Opus parse error | Zod-equivalent validation | Log to `llm_calls` with `status=parse_error`, alert Slack |

---

## 3. Email Classification — `workflows/03-email-classification.json`

### Purpose
A shared inbox stops being a black hole. Every unseen email is classified within 5 minutes and routed to the right channel.

### Trigger
n8n IMAP Email node — polls every 5 minutes for `UNSEEN` flag.

### Node graph

```
IMAP (poll every 5 min, UNSEEN)
  → Function: strip HTML, extract body + subject + from + thread headers
  → HTTP Request → Anthropic Claude (Haiku 4.5)
  → Zod-equivalent validation (category + urgency + confidence)
  → Switch on category (4 rules + fallback):
      all 5 outputs converge at one Slack node; URL is a ternary expression:
        $env.SLACK_WEBHOOK_SALES / SUPPORT / RECRUITING / BILLING / OTHER
      each category therefore routes to its own channel via its own webhook URL
  → Supabase Insert → llm_calls       (runs unconditionally from Validate Classification)
  (mark-as-seen: postProcessAction="nothing" — n8n 1.71.3 Email Trigger has no downstream
   IMAP flag API; emails stay UNSEEN until re-poll; mark-seen-after-success requires Phase 2
   using a Code node with a raw IMAP STORE command or a separate IMAP action credential)
  (error workflow → Slack + error_log; email NOT marked seen on failure)
```

### Expressions
- Body extraction: `$json.text || $json.html?.replace(/<[^>]+>/g, '')`
- Confidence floor: `$json.output.confidence >= 0.6` (below → route to `#inbox-other` regardless of category)

### Retry policy
Max **2 attempts** on Anthropic HTTP node. If both fail, email is left unread for the next poll cycle (5 min later). After 3 consecutive cycles of failure, alert Slack.

### Output schema
```json
{
  "category": "sales|support|recruiting|billing|other",
  "urgency": "low|medium|high",
  "confidence": 0.0-1.0,
  "summary": "1-sentence what-they-want"
}
```

### Failure modes
| Failure | Detection | Action |
|---|---|---|
| IMAP cert error | IMAP node | Alert Slack with `error_log.kind='imap_tls'`; see `TROUBLESHOOTING.md` |
| Classification confidence < 0.6 | Function node post-validation | Route to `#inbox-other` instead of misrouting |
| Anthropic 429 | HTTP node retry | Email stays UNSEEN; next 5-min poll retries naturally |

---

## Cross-workflow conventions

- **Workflow IDs** (stable strings used in `llm_calls.workflow_id`): `lead-qualification`, `daily-content-brief`, `email-classification`.
- **Error workflow**: a single shared error-handler subflow imported by all three workflows. Posts to `#autostream-errors` and inserts a row into `error_log`.
- **Prompt caching**: system prompts on the Anthropic HTTP node use `cache_control: { type: "ephemeral" }` to avoid re-billing the boilerplate on every call.
- **Cost telemetry**: every `llm_calls` row carries `cost_usd` calculated client-side from `usage.input_tokens` + `usage.output_tokens` and the model's per-million pricing.

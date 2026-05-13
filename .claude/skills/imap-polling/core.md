# IMAP Polling — Core

Hot-path config for workflow 3's email-trigger node and the mark-as-seen safety pattern.

## IMAP trigger config

```json
{
  "parameters": {
    "mailbox": "INBOX",
    "downloadAttachments": false,
    "format": "simple",
    "options": {
      "customEmailConfig": "UNSEEN",
      "forceReconnect": 30,
      "allowUnauthorizedCerts": false
    },
    "postProcessAction": "nothing"
  },
  "credentials": {
    "imap": { "id": "imap-prod", "name": "AutoStream IMAP" }
  },
  "type": "n8n-nodes-base.emailReadImap",
  "typeVersion": 2
}
```

Critical settings:

- **`customEmailConfig: "UNSEEN"`** — only fetch emails not yet processed.
- **`postProcessAction: "nothing"`** — DO NOT auto-mark-seen. We mark seen *after* classification succeeds; otherwise an Anthropic failure loses the email forever.
- **`allowUnauthorizedCerts: false`** — TLS verification stays on. Cert errors are loud (correct behavior). See `docs/TROUBLESHOOTING.md`.
- **`forceReconnect: 30`** — minutes between full reconnects; balances stability with rate-limit avoidance.

## Polling cadence

n8n's IMAP trigger polls on a fixed interval (default 60s, configurable). For AutoStream:

- 5-minute cadence is sufficient — shared-inbox routing doesn't need sub-minute latency.
- Set via workflow Settings → "Trigger" → polling interval.
- Could go lower (every 60s) at marginal cost; could go higher (10 min) if Anthropic rate-limit becomes a concern.

The IDLE alternative (push-style notifications from the IMAP server) isn't widely supported by free mail providers — Gmail does, Fastmail does, most others don't. Phase 1 sticks with polling.

## Mark-as-seen after success

Pattern: after classification + Slack routing + Supabase log, fire a separate IMAP node configured to mark the email seen.

```json
{
  "parameters": {
    "operation": "update",
    "messageId": "={{$json.uid}}",
    "flags": ["\\Seen"]
  },
  "type": "n8n-nodes-base.emailReadImap"
}
```

Wire this as the LAST node in the success path. If anything earlier fails:
- The email stays UNSEEN.
- Next 5-min poll re-fetches it.
- After 3 consecutive cycles of failure, the error workflow fires an alert (deduplicate by Message-ID in `error_log.context.message_id`).

## Body extraction

The IMAP node returns `text`, `html`, `subject`, `from`, `to`, `messageId`. For classification, you want clean plaintext:

```javascript
// Function node — clean body
const raw = $json.text || ($json.html || '').replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim();
// Truncate to reasonable size for Claude (4-8k chars covers most legitimate emails)
const body = raw.slice(0, 8000);
return [{
  json: {
    ...$json,
    body_clean: body,
    body_truncated: raw.length > 8000,
  }
}];
```

## Threading awareness

Email Classification doesn't currently use threading — each email is classified independently. If you later want to maintain context across a thread:

- Use `$json.references` (RFC 5322 References header) to find prior messages.
- Look up prior classification in `llm_calls.output->>'category'` for the thread's earliest UID.
- Bias the new classification toward the prior one if confidence < 0.7.

Phase 1 keeps it stateless. Threading is a Phase 2+ refinement if accuracy demands it.

## Credentials

Use n8n's saved credentials (Settings → Credentials → IMAP), not env vars on the IMAP node. The encryption key (rule 04) protects them at rest.

The credential references `$env.IMAP_*` values through the credential editor — but the credential itself is the level of indirection. Workflow JSONs reference `"credentials": { "imap": { "id": "imap-prod" } }` by id, NOT by inline values.

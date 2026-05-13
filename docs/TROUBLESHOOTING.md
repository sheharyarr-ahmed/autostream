# Troubleshooting

Common failures, what they look like, what to do.

---

## n8n won't start: "Encryption key has changed"

**Symptom:**
```
There is an encryption key mismatch. The credentials saved by n8n cannot be decrypted.
```

**Cause:** `N8N_ENCRYPTION_KEY` in `.env` differs from the one used when credentials were originally saved (stored in `n8n_data/config`).

**Fix:**
- If you just generated a new key: don't. Restore the original from your secrets vault.
- If you lost the key: you must delete `n8n_data/` (loses saved credentials) and re-enter every credential. The workflow JSONs themselves are unaffected.

```bash
docker compose down
docker volume rm autostream_n8n_data
docker compose up -d
```

---

## IMAP node: `Error: unable to verify the first certificate`

**Symptom:** Email Classification workflow shows IMAP node errors with TLS chain failures.

**Cause:** Self-signed or non-standard CA on the mail server.

**Fix options** (in order of preference):

1. **Use a different account** — Gmail, Fastmail, ProtonBridge all present standard chains.
2. **Add `tls.rejectUnauthorized = false`** in the IMAP node's options. **Security cost**: any TLS MITM is undetectable. Acceptable for personal demo; never in production.
3. **Pin the CA cert** in the n8n container — mount it via volume and set `NODE_EXTRA_CA_CERTS`.

---

## Anthropic 429 ("rate limit exceeded")

**Symptom:** `llm_calls.status='api_error'` rows appearing with HTTP 429 in body.

**Cause:** Burst exceeded your Anthropic tier's per-minute or per-day cap.

**Fix:**
- Short-term: the workflow's bounded retry (max 2, 4s backoff) covers transient spikes.
- Sustained: see `SCALING.md` Phase C (rate limiting with token bucket).
- Specific to Haiku 4.5 + Opus 4.7: separate limits — Haiku-heavy traffic doesn't free up Opus quota and vice versa.

---

## Slack 429 ("rate_limited")

**Symptom:** Slack node errors `rate_limited`; the row still lands in `llm_calls` but no message appears in the channel.

**Cause:** Slack incoming-webhook limit is ~1 message/sec per webhook. The Content Brief workflow can spike if a feed dumps 50 items at once.

**Fix:**
- The workflow already throttles by posting **one brief per cron tick**, not per item.
- If you still hit 429s, batch alerts (one Slack post listing N qualified leads) rather than firing one per webhook.
- Workspace-level limits (~10 webhook calls/sec across all webhooks) — if you're hitting these, you're past portfolio-demo volume; see `SCALING.md`.

---

## Webhook returns 401 "Invalid signature"

**Symptom:** `curl -X POST /webhook/lead` returns 401; no row in `llm_calls`.

**Cause:** HMAC signature header doesn't match the computed HMAC.

**Fix checklist:**
1. Header name exactly `X-Signature` (case-insensitive at HTTP, but make sure your client sends it).
2. HMAC computed over the **raw request body bytes**, not the JSON-stringified version with whitespace changes.
3. Hex encoding (lowercase), not base64.
4. `WEBHOOK_HMAC_SECRET` matches between client and server `.env`.

Reproduce server-side computation:
```bash
echo -n "$BODY" | openssl dgst -sha256 -hmac "$WEBHOOK_HMAC_SECRET" -r | cut -d' ' -f1
```

---

## Zod-equivalent parse error on LLM output

**Symptom:** `llm_calls.status='parse_error'` with the offending output in `llm_calls.output`.

**Cause:** Claude returned text that doesn't match the schema (missing field, wrong type, extra prose around the JSON).

**Fix path** (don't paper over the error — fix the source):
1. Read the row: `select output from llm_calls where status='parse_error' order by created_at desc limit 5;`
2. Identify the drift pattern (e.g., "rationale" sometimes returns an array instead of string).
3. Tighten the system prompt to be unambiguous about the schema, **and** the Zod schema to reject the drift.
4. If a `cache_control` was set on the system prompt, it'll re-cache on the next call automatically.

---

## docker compose up fails: "port 5678 already in use"

**Symptom:**
```
Bind for 0.0.0.0:5678 failed: port is already allocated
```

**Cause:** Another process (a previous `docker compose` run, or another tool) is holding port 5678.

**Fix:**
```bash
docker compose down
lsof -i :5678              # find the holder
# either kill it, or change N8N_PORT in .env to 5679 and restart
```

---

## Preflight: "all .env.example keys present" passes but workflow still fails

**Symptom:** `scripts/preflight-checks.sh` exits 0 but a workflow node errors with "credentials missing."

**Cause:** Preflight validates that `.env` is complete, not that n8n loaded the credentials. n8n caches credentials inside its own Postgres on first save.

**Fix:** Open the n8n UI → Credentials → re-enter (or re-import) each credential. Or run with `N8N_FORCE_RELOAD_CREDENTIALS=true` once.

---

## Workflow stuck in "running" status forever

**Symptom:** Execution list shows the workflow as `Running` for hours; no completion.

**Cause:** A node is waiting on a network call that's hung (DNS issue, firewall dropping packets silently).

**Fix:**
1. Find the execution: `Executions` tab → click the stuck one → identify which node is "current."
2. Stop the execution from the UI (or via `n8n cli executions:stop --id=<id>`).
3. Add an explicit timeout to that node (HTTP nodes have a `timeout` option; default is unlimited).
4. If it recurs, file a row in `error_log` and gate the workflow behind a circuit breaker (skip if last 3 runs all timed out).

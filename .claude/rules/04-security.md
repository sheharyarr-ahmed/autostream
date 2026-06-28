# Rule 04 — Security

## Webhook authentication

Every incoming webhook is HMAC-SHA256 signed. The webhook node's first child is a Function node that:

1. Reads `X-Signature` header.
2. Computes `crypto.createHmac('sha256', $env.WEBHOOK_HMAC_SECRET).update(rawBody).digest('hex')`.
3. Constant-time compares against the header. **Never** `==` on raw strings — use `crypto.timingSafeEqual`.
4. On mismatch: do NOT call Claude, do NOT log to `llm_calls`.

> **Current implementation vs. target (Phase 1).** WF1's verify node enforces points 1–3 and, on mismatch, *throws* — so a forged request never reaches Claude or `llm_calls` (the security property holds). It does **not** yet return a clean 401: the webhook acks 200 on receipt and the throw routes to the error workflow. Returning a real 401 and not paging `#autostream-errors` on auth failure is a tracked **pre-public-deploy** hardening item (`docs/PHASE-ROADMAP.md`, Phase 2). The endpoint stays local-only until then.

The HMAC secret rotates by updating `WEBHOOK_HMAC_SECRET` in `.env` and restarting the n8n container. There's no in-band rotation — the cost (5 min downtime) is acceptable for a portfolio-scale demo.

## Secret hygiene

- All secrets live in `.env`. `.env` is in `.gitignore`. `.env.example` contains placeholder values only.
- Never reference a secret literal in a workflow JSON. Always `$env.KEY` or n8n credentials.
- Never log a full webhook payload that contains secrets. Redact before `llm_calls.input` insert:

  ```javascript
  // Function node — redact before logging
  const redacted = { ...$json };
  delete redacted.api_key;
  delete redacted.password;
  delete redacted.authorization;
  return [{ json: { ...$input.first().json, input_for_log: redacted } }];
  ```

## n8n encryption key

- `N8N_ENCRYPTION_KEY` encrypts saved credentials at rest in n8n's internal DB.
- Generate with `openssl rand -hex 32` (64 hex chars = 32 bytes).
- Lost key = lost credentials. There is no recovery. Back it up to a password manager **before** first `docker compose up`.
- ADR 0003 documents the no-rotation policy during the demo phase.

## IMAP TLS

- IMAP uses port 993 with TLS by default.
- `tls.rejectUnauthorized = true` is the default — only override if you know the cost.
- Mail-server certs older than ~2 years often fail chain verification; replace the mail server, don't disable TLS.
- See `TROUBLESHOOTING.md` for cert-error remediation.

## Slack incoming-webhook URLs

- Treat the webhook URL like a secret. Anyone with the URL can post to the channel.
- Revoke + reissue on any suspicion of leak (Slack admin → Apps → Incoming Webhooks → Revoke).
- Rate-limited to ~1 msg/sec per webhook — don't fan out from a workflow without throttling.

## Commit-msg + PreToolUse defense-in-depth

Three layers protect the git history from AI attribution:

1. `.githooks/commit-msg` — blocks attribution tokens at commit time.
2. `.claude/settings.json` PreToolUse hook — blocks `git commit --no-verify` / `--no-gpg-sign` from the Bash tool.
3. This rule + Sheharyar's manual discipline — humans review commits before push.

All three must be intact. Removing any one weakens the discipline.

## What is NOT in scope for Phase 1

- Per-tenant key isolation (multi-tenancy doesn't exist yet — Phase 3).
- HSM-backed key storage. Env vars are fine for the demo.
- DDoS protection on the webhook endpoint. The Railway URL is the only public surface and Railway provides basic protection. Phase 2 adds a Cloudflare proxy.
- Audit log signing. `llm_calls` is append-only by convention but not by enforcement. Phase 3 adds row-level signatures if compliance matters.

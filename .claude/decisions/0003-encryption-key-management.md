# ADR 0003 — N8N_ENCRYPTION_KEY: env only, no rotation in demo phase

**Status:** Accepted (Phase 1)
**Date:** 2026-05-14

## Context

n8n encrypts saved credentials at rest using `N8N_ENCRYPTION_KEY`. Lose the key → all saved credentials become unrecoverable garbage; you must re-enter each one. Rotate the key → same problem unless you re-encrypt the existing DB rows (which n8n doesn't ship as a turnkey CLI).

Options considered:

1. **Env-var only, no rotation** during Phase 1.
2. **Vault-backed** (HashiCorp Vault / AWS KMS) with periodic rotation.
3. **Per-deployment generation** — generate a new key every `docker compose up` (data loss every restart).

## Decision

Use option 1: **env-var only, no rotation, key backed up to a password manager before first `docker compose up`**.

## Rationale

- The demo is single-tenant, single-author, 30-day window. Vault is overkill — its setup time exceeds the demo lifetime.
- Option 3 makes the demo non-resumable across restarts. Worse, it makes the workflows look "fragile" to a reviewer who doesn't know n8n.
- Key rotation in production isn't really about credentials at rest — it's about limiting blast radius if a key leaks. At demo scale, the leak vector is `.env` itself, and the mitigation is `.env` in `.gitignore` + no `.env` commit, both of which AutoStream enforces.

## Operational requirements

- Key generated with `openssl rand -hex 32` (32 bytes = 64 hex chars). Anything shorter is rejected by `scripts/preflight-checks.sh`.
- Key stored in Sheharyar's password manager **before** first deploy.
- Key included in Railway env-var config (via `railway variables set N8N_ENCRYPTION_KEY=...`) — never committed.
- If the Railway env ever resets (rare but possible during plan changes), restore from password manager before restarting the n8n service.

## Consequences

- **Positive**: minimal operational overhead; matches the portfolio-demo blast radius.
- **Negative**: if the key leaks, the only mitigation is generate a new key + wipe the n8n_data volume + re-enter all credentials. Documented in `TROUBLESHOOTING.md`.

## Reconsideration triggers

- Phase 3 multi-tenant introduces per-tenant credentials → Vault becomes proportionate.
- A credential-leak incident → trigger emergency rotation (which means the workflows will need credentials re-entered; document the runbook before that day).

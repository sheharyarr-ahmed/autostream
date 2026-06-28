# Phase Roadmap

AutoStream's evolution from portfolio demo (Phase 1) to multi-tenant SaaS (Phase 3). Each phase is fully shippable on its own — Phase 1 isn't a beta of Phase 2.

---

## Phase 1 — Current (single-tenant demo)

**Goal:** Prove n8n + Claude production-grade work as a portfolio artifact. Run for a 30-day Railway demo window, then hand off the source for engagements.

**In scope:**
- Three workflows (lead, brief, email) — single-instance n8n, internal Postgres
- Anthropic Claude — Haiku 4.5 default, Opus 4.7 for the daily-brief critic only
- Supabase Postgres — observability tables (`llm_calls`, `workflow_runs`, `error_log`)
- Slack notifications — one workspace, dedicated channels per workflow
- HMAC webhook verification + Zod-equivalent LLM output validation
- Bounded retry (max 2) on every external call
- Single-author git history, conventional commits, attribution-blocking hooks

**Out of scope (intentional):**
- Multi-user / multi-org
- Queue mode + worker scaling
- Frontend / dashboard
- Stripe / billing
- BYOK (bring-your-own-key) flows
- Production-grade monitoring (Grafana, alerts beyond Slack)

**Exit criteria (when Phase 1 is "done"):**
1. All commits land with no AI attribution in git history.
2. `bash scripts/preflight-checks.sh` passes on Sheharyar's laptop.
3. `docker compose up -d` brings the stack online; all 3 workflows trigger their canonical demo path.
4. Railway deployment lives at a public URL for 30 days.
5. Loom demo recorded and linked from README.

---

## Phase 2 — Production hardening (multi-source, queue mode)

**Goal:** Take AutoStream from portfolio to deployable-for-a-real-team. Single-tenant still, but operationally robust.

**Additions:**
- **Queue mode**: Redis + 3 n8n worker replicas. See `SCALING.md` Phase A.
- **More content sources**: Bluesky firehose, ATOM feeds, Hacker News API, Twitter list scrapes (when rate-limit permits).
- **More email accounts**: support N IMAP accounts (one set of envs per account); classify across all of them into the same Slack workspace.
- **Rate limiting**: per-model token bucket against Anthropic limits. See `SCALING.md` Phase C.
- **Observability dashboard**: a single SQL view + Supabase visualizations for token spend, p99 latency, parse-error rate.
- **CI**: GitHub Actions workflow that runs `preflight-checks.sh` on every PR + smoke-tests the workflow JSONs against `n8n cli`.
- **Deferred plugin candidates revisited**:
  - `test-writer-fixer` (contains-studio) — only if a `tests/` directory with vitest is added during Phase 2.
  - `conductor` (wshobson) — for managing the multi-source ingestion complexity.
  - `MCP Builder` (agency-agents) — if a custom Supabase MCP for the observability schema becomes useful.

**Exit criteria:**
- Sustained 10× Phase 1 volume (10k webhooks/mo, 100k email classifications/mo) with p99 latency unchanged.
- Anthropic 429 rate < 0.5% sustained.
- Zero credential leaks in committed code (verified by `gitleaks` in CI).

---

## Phase 3 — Multi-tenant (SaaS-shape)

**Goal:** AutoStream as a SaaS product — one deployment serves many small teams, each with their own credentials, workflows, and Slack workspace.

**Additions:**
- **Tenant model**: `tenants` table with FK from `workflow_runs.tenant_id`; row-level security on `llm_calls`.
- **BYOK**: each tenant supplies their own Anthropic API key; AutoStream never pays for tokens.
- **Tenant-scoped Slack OAuth**: instead of a single `SLACK_WEBHOOK_URL`, each tenant authorizes a Slack workspace via OAuth and AutoStream stores the bot token.
- **Billing**: Stripe metered billing keyed off `sum(llm_calls.cost_usd)` per tenant per month + a flat platform fee.
- **Admin UI**: minimal Next.js dashboard for tenant self-service (workflow toggle, key rotation, usage view).
- **Multi-region**: at least US + EU n8n clusters for data-residency-sensitive tenants.

**Out of scope at Phase 3 (still):**
- White-label / per-tenant custom domains
- Workflow-builder UI (n8n's own UI suffices)
- SSO / SAML (deferred to Phase 4 if it happens)

**Exit criteria:**
- First paying tenant onboarded with zero AutoStream-team intervention beyond Stripe webhook activation.
- 99.9% uptime SLA met over a rolling 30-day window.
- Clean separation: no production data flows between tenants in `llm_calls` or any other shared table (verified by RLS smoke tests).

---

## Versioning

- Phase 1: `v0.1.x` (portfolio)
- Phase 2: `v0.5.x` (production-hardened single-tenant)
- Phase 3: `v1.0.x` (multi-tenant)

Phase 1 → 2 transition is the bigger jump in code volume. Phase 2 → 3 is the bigger jump in product scope.

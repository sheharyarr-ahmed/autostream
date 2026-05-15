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
1. All 16 commits land with no AI attribution in history.
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

---

## Phase 2: Workflow JSON validation (deferred from Phase 1, May 15 2026)

### Why deferred
End-to-end smoke testing of Phase 0-scaffolded workflow JSONs surfaced 6 schema/architectural issues that require careful resolution rather than rapid iteration. Decision made at 3:30 AM Pakistan time to lock in stable infrastructure commits and defer workflow validation to fresh-eyes session.

### Issues identified (require resolution before workflows execute)
1. Workflow 1 (Lead Qualification):
   - Function node Verify HMAC requires NODE_FUNCTION_ALLOW_BUILTIN=crypto env var
   - Function vs Code node decision: Function v1 supports $headers/$json magic, Code v2 doesn't
   - HMAC accessor pattern needs alignment with chosen node type
2. All workflows:
   - HTTP Request nodes need specifyBody: 'json' parameter
   - errorWorkflow references point to non-existent error handler
   - Webhook nodes need stable webhookId UUIDs
3. Workflow 2 (Daily Content Brief):
   - Split-In-Batches node wiring malformed
4. Workflow 3 (Email Classification):
   - customEmailConfig parameter handling

### Architectural decisions needed
- Function node (n8n-nodes-base.function v1) vs Code node (n8n-nodes-base.code v2) — both have trade-offs
- HMAC verification location: inside n8n workflow vs reverse-proxy layer
- Whether to add NODE_FUNCTION_ALLOW_BUILTIN=crypto permanently (security implication)

### Stable foundation (already shipped)
- Healthcheck diagnostic and IPv4 loopback fix (commit 8017eab)
- Env var forwarding to n8n container (commit 53ecdae)
- Supabase observability schema with RLS (Gate 2 verified)
- All cloud services provisioned (Anthropic, Supabase, Slack, Gmail IMAP)
- All credentials configured (.env complete, backed up to Apple Notes)

### Next session checklist
1. Read this note first
2. Run docker compose ps to verify containers still healthy
3. Decide: revert to Function node + crypto env var, OR adapt to Code node + new accessor pattern
4. Apply chosen pattern uniformly across all 3 workflows
5. End-to-end smoke test with fresh eyes
6. Push the workflow fixes as a separate clean commit cluster

### What NOT to do next session
- Don't ship partially-working workflows; smoke tests must pass cleanly
- Don't defer the architectural decision further; pick Function OR Code, then commit to that path
- Don't expand scope to Railway deploy until all 3 workflows verified
- Don't post to LinkedIn until smoke tests are green

---

## Phase 2.1: Workflow body syntax rebuild (deferred from Phase 2, May 16 2026)

### Status of Phase 2

**Shipped (May 16 2026)** — five source-cited fixes plus one env-var addition, all verified via partial smoke test:

1. **HMAC accessor pattern** (wf1 Verify HMAC node) — `$headers['x-signature']` → `$json.headers['x-signature']`, `JSON.stringify($json)` → `JSON.stringify($json.body)`. Source: `packages/workflow/src/WorkflowDataProxy.ts` at tag `n8n@1.71.3`. Confidence: 9/10 → **verified working**.
2. **customEmailConfig removal** (wf3 IMAP Trigger) — invalid `"UNSEEN"` literal removed; default `["UNSEEN"]` applies. Source: `packages/nodes-base/nodes/EmailReadImap/v2/EmailReadImapV2.node.ts` at tag `n8n@1.71.3`. Confidence: 10/10 → **verified working** (wf3 activates).
3. **Anthropic content double-stringify** (wf1 Anthropic — Score Lead) — `JSON.stringify($json)` → `JSON.stringify(JSON.stringify($json))`. Fixes n8n splicing the object as raw JSON instead of as a string. Confidence: 9/10 → **verified working** (Claude returned `score=85`).
4. **Validate-node fence stripping** (all 3 Validate nodes) — strip ` ```json...``` ` markers before `JSON.parse`. Handles Claude's intermittent markdown-fence quirk. Confidence: 9.5/10 → **verified working in wf1**.
5. **`NODE_FUNCTION_ALLOW_BUILTIN=crypto`** in `docker-compose.yml` n8n service env — unblocks `require('crypto')` for HMAC verification. **Verified working** end-to-end.

Plus the 4-bullet fix cluster from the prior session (webhookId, specifyBody, errorWorkflow, Split-In-Batches wiring) which all still apply and are verified.

### Smoke test 3a evidence (May 16, 2026 session)

Webhook → HMAC verify → Anthropic call → Validate Output → Score threshold IF → reached Slack node. End-to-end chain confirms HMAC + Anthropic + Validate work in production. Failure point is downstream Slack jsonBody — covered below.

### What remains in Phase 2.1

**Bug 8: hybrid jsonBody syntax in Slack and Supabase HTTP nodes** across all 3 workflows.

Scaffolded pattern (broken):

```
"jsonBody": "={\"blocks\":[{\"text\":\"prefix \"+$json.parsed.score}]}"
```

The leading `=` puts n8n in JS-expression mode, but the body mixes bare JS string concatenation (`"prefix "+$json.field`) inside JSON-string literals. n8n's expression engine doesn't accept this hybrid.

Working pattern (per the wf1 Anthropic node which succeeded):

```
"jsonBody": "={\"messages\":[{\"content\":{{JSON.stringify(JSON.stringify($json))}}}]}"
```

i.e. use `{{...}}` interpolation markers for substitutions, not bare `+` concatenation.

**Affected nodes** (8 total):
- wf1: Slack — Qualified Lead, Supabase — Insert llm_calls, Supabase — Insert workflow_runs
- wf2: Slack — Brief, Supabase — Insert llm_calls, Supabase — Archive Briefs
- wf3: Slack — Route to Channel, Supabase — Insert llm_calls

### Recommended Phase 2.1 approach: rebuild via n8n UI

Rather than continue the archaeological fix loop on hand-authored JSON (now at 7 surfaced scaffold bugs from Phase 0), use the n8n UI to author the Slack and Supabase nodes correctly, then export the resulting JSON and replace the current files.

**Steps:**
1. In n8n UI, open `01 — Lead Qualification` (already imported).
2. Replace the Slack and Supabase nodes manually — use the UI's drag-and-drop body editor, which generates n8n-canonical jsonBody syntax.
3. Save in the UI (n8n auto-fills any missing fields like `webhookId`, valid `customEmailConfig`, etc.).
4. Export the workflow JSON from the UI (Workflow → Download).
5. Replace `workflows/01-lead-qualification.json` with the exported file.
6. Repeat for wf2 and wf3.
7. Re-import via API (DELETE old, POST new from exported file, activate).
8. Re-run smoke 3a → 3b → 3c.

### The 7-bug archaeological cycle (Phase 0 scaffold record)

This catalog exists so the lesson sticks: hand-authoring n8n workflow JSON without UI validation produces brittle output. Phase 0 prioritized "everything runnable from source" without an n8n instance to validate against, so the schema mismatches accumulated silently:

| # | Bug | Surfaced via | Fixed in |
|---|---|---|---|
| 1 | Webhook node missing `webhookId` (production URL not registered) | smoke 3a 404 | Phase 2 bullet #1 |
| 2 | HTTP nodes missing `specifyBody: 'json'` | Anthropic 400 "model required" | Phase 2 bullet #2 |
| 3 | `settings.errorWorkflow` references nonexistent workflow | activation warning | Phase 2 bullet #3 |
| 4 | wf2 Split-In-Batches `done` output orphaned | static review | Phase 2 bullet #4 |
| 5 | wf3 `customEmailConfig: "UNSEEN"` not valid JSON | activation failure | Phase 2.0 Edit 2 |
| 6 | wf1 Anthropic `content` field encoded as object not string | Anthropic 400 array-expected | Phase 2.0 Edit 3 |
| 7 | Validate nodes don't strip Claude's markdown fence | parse error on real response | Phase 2.0 Edit 4 (×3 nodes) |
| 8 | Slack/Supabase jsonBody mixes `=` JS-mode with `+` concat | smoke 3a Slack node error | **Phase 2.1 (deferred)** |

### Anthropic spend during Phase 2 smoke testing

Total: ~$0.002 of $0.50 budget. Anthropic was actually called successfully in attempt 5 (one Haiku call returning a real score). Earlier attempts short-circuited before the API.

### Next session checklist (Phase 2.1)

1. Read this section.
2. Confirm containers healthy (`docker compose ps`).
3. Open n8n UI at http://localhost:5678.
4. For each of wf1/wf2/wf3: rebuild Slack and Supabase nodes via UI body editor, save, export.
5. Replace `workflows/*.json` with UI-exported versions.
6. Diff carefully against current files; confirm only the 8 hybrid-syntax nodes changed.
7. Re-import via API (DELETE existing, POST new, activate).
8. Smoke test 3a (full chain to Supabase insert + Slack post).
9. If 3a passes: 3b, 3c.
10. Bundle commit on green.

### What NOT to do in Phase 2.1
- Don't continue the archaeological fix loop on hand-authored body syntax. UI-export is the higher-leverage path.
- Don't ship until full chain (HMAC → Anthropic → Validate → Slack + Supabase write) is verified end-to-end with a row visible in `llm_calls`.
- Don't expand scope to Railway deploy until Phase 2.1 closes.
- Don't post the Loom demo until Phase 2.1 closes.

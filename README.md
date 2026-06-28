<p align="center">
  <img src="assets/icon-glow-512.png" alt="AutoStream" width="160" />
</p>

<h1 align="center">AutoStream</h1>

<p align="center">
  <b>Production-grade AI automation, observable by design.</b><br/>
  Three independent n8n + Claude workflows — every LLM call logged, every webhook signed, every output validated.
</p>

<p align="center">
  <a href="#what-autostream-does">About</a> ·
  <a href="#deployment">Deployment</a> ·
  <a href="#quickstart">Quickstart</a> ·
  <a href="docs/WORKFLOWS.md">Workflows</a> ·
  <a href="#architecture">Architecture</a> ·
  <a href="#observability">Observability</a> ·
  <a href=".claude/decisions/">Decisions</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/orchestration-n8n-EA4B71?style=flat-square" alt="n8n" />
  <img src="https://img.shields.io/badge/LLM-Anthropic_Claude-D97757?style=flat-square" alt="Anthropic Claude" />
  <img src="https://img.shields.io/badge/observability-Supabase-3FCF8E?style=flat-square" alt="Supabase" />
  <img src="https://img.shields.io/badge/license-MIT-2D6CDF?style=flat-square" alt="MIT" />
</p>

---

> **Status:** Deployed to Railway — self-hosted n8n on Docker behind a public HTTPS endpoint. All three workflows verified green end-to-end **in production** — real Anthropic calls, real Slack alerts, real Supabase rows. The lead webhook is HMAC-gated: a forged or missing signature is rejected with a clean `401` before any model call. Source open.

---

## TL;DR

AutoStream is a reference implementation of three high-leverage n8n workflows that small teams build over and over, badly:

1. **Lead Qualification** — score inbound leads with Claude, alert sales in Slack, log to Postgres.
2. **Daily Content Brief** — pull RSS at 9 AM, distill with Claude, post to Slack, archive to Postgres.
3. **Email Classification** — poll inbox via IMAP, categorize with Claude, route to the right Slack channel.

What makes this different from a tutorial:

- Every LLM call is observable — input, output, duration, tokens, cost, all in Supabase.
- Zod-validated outputs — no silent prompt drift; malformed responses fail loudly.
- Bounded retry (max 2 attempts) — no runaway loops, no cost blowouts.
- HMAC-verified webhooks — no spoofed triggers.
- Single-author git history — clean attribution, conventional commits, no AI footprints.

Built for the founder or marketing operator who needs production automation, not toys.

---

## Demo

Measured on the local stack (single run each; latency is wall-clock end-to-end):

| Workflow | Trigger | Latency | Cost per run | Model |
|---|---|---|---|---|
| Lead Qualification | webhook | ~5s | $0.0006 | Haiku 4.5 |
| Daily Content Brief | cron 09:00 PKT | ~40s (3 feeds) | $0.20 | Opus 4.7 |
| Email Classification | IMAP poll | ~6s | $0.0004 | Haiku 4.5 |

Costs are the actual `cost_usd` values logged to `llm_calls` for one run each — exactly the kind of figure the observability layer exists to surface. The brief is ~300× the others: Opus 4.7 plus ~50 candidate articles of input. At daily cadence that's ~$6/month, which is precisely the signal the cost tables in `rules/05-cost-control.md` are designed to catch before it surprises you.

---

## The Problem

Most n8n workflows in the wild fail one of these tests:

- LLM outputs aren't validated → silent corruption downstream.
- Retries aren't bounded → API bills explode on a bad day.
- No observability → debugging requires re-running the workflow.
- Webhooks aren't authenticated → anyone can trigger them.
- Secrets leak into exported workflow JSON.

AutoStream solves all five for the three workflows most small teams actually need.

---

## What AutoStream Does

### 1. Lead Qualification

**Trigger:** `POST /webhook/lead` (HMAC-signed).
**Flow:** Receive payload → Claude Haiku 4.5 scores fit, intent, urgency → if score ≥ threshold, post enriched alert to `#sales-leads`; always log to `llm_calls` + `workflow_runs`.
**Return:** Sales sees the high-intent lead in Slack within 2 seconds; everyone else lands in the Supabase queue for follow-up.

### 2. Daily Content Brief

**Trigger:** Cron at 09:00 Asia/Karachi.
**Flow:** Read N RSS feeds → dedupe by GUID against last 24h → Claude Opus 4.7 (critic) selects + summarizes top items → post brief to `#daily-brief` → archive picks to `content_briefs`.
**Return:** The team starts the day with the three things that matter, distilled into 200 words, every day, without anyone reading 50 feeds.

### 3. Email Classification

**Trigger:** IMAP poll (Gmail).
**Flow:** Fetch unseen → Claude Haiku 4.5 classifies into `{sales, support, recruiting, billing, other}` + extracts urgency and confidence → Switch routes each category to its **own** Slack webhook (`SLACK_WEBHOOK_{SALES,SUPPORT,RECRUITING,BILLING,OTHER}`) → mark seen → log to `llm_calls`.
**Return:** A shared inbox stops being a black hole. Each email surfaces in Slack, tagged with its category, within a minute.

---

## What AutoStream Makes Measurable

Every architectural choice exists so you can answer these questions about your own deployment without re-running anything:

- **Token spend per workflow** — `select workflow_id, sum(cost_usd) from llm_calls group by workflow_id`.
- **p50 / p99 latency per workflow** — straight from `workflow_runs.duration_ms`.
- **LLM parse-error rate** — `select count(*) filter (where status = 'parse_error')::float / count(*) from llm_calls`.
- **Lead-score distribution** — `select avg((output->>'score')::int) from llm_calls where workflow_id = 'lead-qualification'`.
- **Classification accuracy over time** — join `llm_calls.output` against human corrections in `email_corrections`.

What gets measured gets improved. AutoStream treats the LLM as a service to be observed, not a black box to be hoped at.

---

## Architecture

```mermaid
flowchart LR
  subgraph Triggers
    W[Webhook /lead]
    Cr[Cron 09:00 PKT]
    Im[IMAP poll]
  end

  RSS[RSS feeds] --> Cr

  W  --> WF1[Lead Qualification]
  Cr --> WF2[Daily Content Brief]
  Im --> WF3[Email Classification]

  WF1 --> CL((Anthropic Claude))
  WF2 --> CL
  WF3 --> CL

  WF1 --> SL[Slack]
  WF2 --> SL
  WF3 --> SL

  WF1 --> SB[(Supabase Postgres)]
  WF2 --> SB
  WF3 --> SB

  WF1 -.error.-> SL
  WF2 -.error.-> SL
  WF3 -.error.-> SL
```

Three workflows, fully isolated. No shared state in n8n — only in Postgres, treated as an event log.

---

## Stack

| Layer | Choice | Why | ADR |
|---|---|---|---|
| Orchestration | n8n Community Edition (Docker, self-hosted) | Open source, no per-execution fees, visual debuggability | — |
| Hosting | Railway free trial ($5 credit, 30-day demo) | Zero-config Docker, public URL, free for demo period | [0001](.claude/decisions/0001-deployment-railway-free-trial.md) |
| LLM | Anthropic Claude — Haiku 4.5 + Opus 4.7 | Haiku for routing/classification; Opus reserved for critic nodes | [0006](.claude/decisions/0006-haiku-vs-opus-model-tiering.md) |
| Observability | Supabase Postgres (free tier) | Remote-inspectable LLM call log, free, durable | [0007](.claude/decisions/0007-supabase-over-sqlite.md) |
| Content source | RSS (no API key) | Replaces NewsAPI — no key, no quota | [0004](.claude/decisions/0004-rss-over-newsapi.md) |
| Email source | IMAP polling | Replaces Gmail Pub/Sub — no GCP project required | [0005](.claude/decisions/0005-imap-over-gmail-pubsub.md) |
| Notifications | Slack incoming webhooks | Free workspace tier, ubiquitous | — |
| Output validation | Zod | Load-bearing safety net for LLM outputs | [0008](.claude/decisions/0008-zod-validation-llm-outputs.md) |

---

## Observability

Every LLM call writes one row to `llm_calls`:

```sql
create table llm_calls (
  id              uuid primary key default gen_random_uuid(),
  workflow_id     text not null,
  workflow_run_id text not null,            -- n8n execution id (integer-as-text)
  model           text not null,
  prompt_tokens   int  not null,
  output_tokens   int  not null,
  duration_ms     int  not null,
  cost_usd        numeric(10, 6) not null,
  input           jsonb not null,
  output          jsonb not null,
  status          text not null check (status in ('ok', 'parse_error', 'api_error')),
  created_at      timestamptz default now()
);
create index on llm_calls (workflow_id, created_at desc);
create index on llm_calls (status) where status != 'ok';
```

`workflow_run_id` is `text`, not `uuid` — n8n execution ids are sequential integers, so the run-id columns store the real execution id to link a row back to its n8n execution page. Two more tables — `workflow_runs` and `error_log` — capture per-run metadata and failures. Full DDL in [`supabase/migrations/0001_observability_tables.sql`](supabase/migrations/0001_observability_tables.sql); the run-id retype is in [`0002_exec_id_text.sql`](supabase/migrations/0002_exec_id_text.sql); the `error_log.attempt_count` column is in [`0003_error_log_attempt_count.sql`](supabase/migrations/0003_error_log_attempt_count.sql).

---

## Deployment

AutoStream is deployed to **Railway** as two services — n8n (`n8nio/n8n`, version-pinned) and a Postgres for n8n's own state. All n8n state lives in Postgres and the encryption key is supplied as an env var, so no persistent volume is needed; observability still writes to Supabase. The lead webhook is public over HTTPS.

The HMAC gate is verified **in production**:

- Forged / missing signature → `HTTP 401 {"error":"unauthorized"}`, with **zero** `llm_calls` and **zero** `error_log` rows (rejected before any model call; auth failures don't page the error channel).
- Valid signature → `HTTP 200`, full chain logged to Supabase (`llm_calls` + `workflow_runs`) and a Slack alert for qualified leads.

The live demo runs on Railway's free trial ($5 / 30-day window), so the public URL is time-boxed. The same Docker image + env configuration deploys to any host for a permanent install — see [`docs/PHASE-ROADMAP.md`](docs/PHASE-ROADMAP.md).

---

## Quickstart

Prerequisites: Docker, an Anthropic API key, a Supabase project, a Slack incoming-webhook URL.

```bash
git clone https://github.com/sheharyarr-ahmed/autostream.git
cd autostream
cp .env.example .env       # fill in keys
git config core.hooksPath .githooks
bash scripts/preflight-checks.sh
docker compose up -d
```

Open `http://localhost:5678` → log in with `N8N_BASIC_AUTH_*` from `.env` → **Import from File** → select each JSON under `workflows/`.

Apply the Supabase migrations (in order), or paste them into the Supabase SQL editor:

```bash
psql "$SUPABASE_URL" -f supabase/migrations/0001_observability_tables.sql
psql "$SUPABASE_URL" -f supabase/migrations/0002_exec_id_text.sql
psql "$SUPABASE_URL" -f supabase/migrations/0003_error_log_attempt_count.sql
```

Note: the IMAP node (Workflow 3) needs an IMAP credential created in the n8n UI and attached before activation; the Postgres node (Workflow 1) needs a Postgres credential pointing at your Supabase pooler. Webhook (WF1) and HTTP nodes read secrets from `$env`.

Trigger a test lead. The HMAC is computed over the **exact** request body, so sign and send the same string:

```bash
BODY='{"email":"test@example.com","intent":"buy","budget":"50k","message":"ready to buy"}'
SIG=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$WEBHOOK_HMAC_SECRET" | awk '{print $NF}')
curl -X POST http://localhost:5678/webhook/lead \
  -H "Content-Type: application/json" \
  -H "x-signature: $SIG" \
  -d "$BODY"
```

A qualified lead (score ≥ 70) fires a Slack alert within a few seconds; every call lands in `llm_calls` regardless of score.

---

## Project Structure

```
autostream/
├── workflows/                 # 3 n8n workflow JSONs + shared error handler
├── supabase/migrations/       # observability schema
├── assets/                    # brand assets — icon, favicons, social card
├── docs/                      # WORKFLOWS, SCALING, TROUBLESHOOTING, PHASE-ROADMAP
├── .claude/                   # Claude Code project context (agents, skills, rules, ADRs)
├── .githooks/commit-msg       # blocks AI attribution in commit messages
├── scripts/preflight-checks.sh
└── docker-compose.yml
```

---

## Documentation

- [`docs/WORKFLOWS.md`](docs/WORKFLOWS.md) — per-workflow spec (nodes, expressions, error paths)
- [`docs/SCALING.md`](docs/SCALING.md) — what changes at 100× volume (queue mode, workers, pool sizing)
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) — encryption-key mismatches, IMAP TLS, 429 handling
- [`docs/PHASE-ROADMAP.md`](docs/PHASE-ROADMAP.md) — Phase 1 (current) → Phase 2 (queue mode + more sources) → Phase 3 (multi-tenant)
- [`.claude/decisions/`](.claude/decisions/) — 8 ADRs covering every load-bearing choice

---

## Limitations

- **Time-boxed demo host.** The live deployment runs on Railway's free trial (30-day window); the public URL expires with it. A permanent install needs a paid host or a long-running self-host — the Docker image + env config is unchanged either way.
- **Single-tenant.** No org/user model. One n8n instance per deployment.
- **No queue mode.** All execution in-process. Scaling notes in `docs/SCALING.md`.
- **English-only prompts.** Multilingual classification not tuned.

---

## About

Built by [Sheharyar Ahmed](https://sheharyarr.dev) — AI-native software engineer, MERN + Native iOS + Python AI. AutoStream is a production-grade reference implementation for n8n + Claude automation — the second build in **Project Auto-Stream**, a portfolio series of production-grade automation projects.

Need custom AI agents or production automation built for your team? Visit the studio — **[SheryLabs](https://sherylabs.com)**. Also available for n8n + Claude API engagements on Upwork.

---

## License

MIT.

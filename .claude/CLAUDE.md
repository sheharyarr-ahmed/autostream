# AutoStream — Project Preamble

Loaded automatically into every conversation in this repo. Project-local context that supplements (does not replace) the global `~/.claude/CLAUDE.md`.

## What this project is

AutoStream is a public portfolio artifact (asset #2 of Project Auto-Stream). Three independent n8n workflows, each calling Anthropic Claude and logging to Supabase Postgres. The git history, the architecture decisions, and the discipline of the scaffolding *are themselves the deliverable*.

The audience for this repo:

1. An Upwork client (founder / ops lead / marketing manager) skimming the README.
2. A senior engineer they ask to vet the work before hiring.

Both must come away convinced this is production-grade.

## Locked tech stack (non-negotiable for Phase 1)

- **Orchestration**: n8n Community Edition, Docker, self-hosted.
- **Hosting**: Railway free trial ($5 credit, 30-day demo window).
- **LLM**: Anthropic Claude — Haiku 4.5 for routing/classification, Opus 4.7 for the daily-brief critic.
- **Observability**: Supabase Postgres (free tier).
- **Notifications**: Slack incoming webhooks.
- **Email source**: IMAP polling.
- **Content source**: RSS feeds.
- **Output validation**: Zod-equivalent in Function nodes.

Replacing any of these is a strategic pivot, not an implementation detail. See `decisions/` for the ADRs.

## Non-negotiable constraints

- **Zero cash spending** in Phase 1. Free tiers + existing Anthropic credits only. See `rules/05-cost-control.md`.
- **Bounded retry** (max 2 attempts) on every external call. See `rules/03-workflow-design.md`.
- **Full observability**: every LLM call writes one row to `llm_calls`. Even failed calls. Even parse errors.
- **HMAC-verified webhooks**. See `rules/04-security.md`.
- **No silent failures**: every error fires Slack alert + writes `error_log`.
- **Single-author git history**, no AI attribution anywhere, ever. See `rules/02-git-discipline.md`.

## Where to look

- **What each workflow does, node-by-node**: `docs/WORKFLOWS.md`.
- **Why we chose X over Y**: `decisions/0001-0008-*.md`.
- **Hard rules that govern any new code/workflow**: `rules/01-05-*.md`.
- **Hot-path knowledge for specific concerns** (n8n nodes, Claude API, Supabase schema, etc.): `skills/`.
- **Agent specializations** for delegating focused work: `agents/`.
- **Phase plan**: `docs/PHASE-ROADMAP.md`.

## Operating discipline (Karpathy-derived)

1. **Think before coding.** Don't assume — state assumptions or ask. Push back when a simpler approach exists.
2. **Simplicity first.** Minimum code, no speculative features. If 200 lines could be 50, rewrite.
3. **Surgical changes.** Touch only what the task requires. Match existing style. Don't delete unrequested.
4. **Goal-driven execution.** Verifiable success criteria. "It works" is not a criterion.

## Anti-fabrication (hard)

Don't claim AutoStream uses tech it doesn't use. Don't invent workflow capabilities that aren't in the JSONs. Don't reference ADRs that don't exist. If asked about something not in `decisions/`, say so.

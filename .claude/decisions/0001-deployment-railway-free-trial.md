# ADR 0001 — Deployment: Railway free trial for 30-day demo window

**Status:** Accepted (Phase 1)
**Date:** 2026-05-14

## Context

AutoStream is a public portfolio artifact. It needs to be **runnable by a stranger** within minutes (not just source-readable), and it must cost AutoStream zero cash during the demo window. The candidate deployment targets:

- **Railway** — free $5 trial credit, 30-day window, zero-config Docker deploys, public URL out of the box.
- **Render** — free tier sleeps after 15 min idle; cold starts kill webhook latency.
- **Fly.io** — generous free tier but requires paid credit card up front; more setup friction.
- **Self-host on a homelab VPS** — zero cost ongoing but no public access guarantee, and no portfolio-grade URL.
- **AWS / GCP** — free tier exists but requires significant config; high accidental-spend risk.

## Decision

Use **Railway free trial**.

## Consequences

- **Positive**: zero-config Docker deploy from `docker-compose.yml`; public HTTPS URL; no cold starts; visible to Upwork clients clicking through.
- **Positive**: ~$3 of the $5 credit covers a 30-day demo window with low traffic.
- **Negative**: demo expires after 30 days. After that, the README points readers to local `docker compose up`, or Sheharyar self-funds an extension.
- **Negative**: Railway lock-in for the demo. Mitigated by: deploy IS just `docker-compose up`, so any Docker host can take the workload after Phase 1.

## Reconsideration triggers

- Railway changes free-trial terms (likely; trials evolve).
- Demo extension requested by a real prospect → consider paid tier or move to homelab + Cloudflare Tunnel.
- Phase 2 begins → reassess; queue mode + workers may push beyond free-trial budget anyway.

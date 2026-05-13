# ADR 0004 — Ingestion: RSS over NewsAPI

**Status:** Accepted (Phase 1)
**Date:** 2026-05-14

## Context

Workflow 2 (Daily Content Brief) needs a content source. Two options:

- **NewsAPI** — clean JSON API, broad publisher coverage, requires an API key, free tier limits to 100 requests/day and 24-hour delayed articles.
- **RSS feeds** — universal protocol, every publisher offers one, no API key, no rate limit, real-time, requires per-feed dedup logic.

## Decision

Use **RSS feeds**. The list of feed URLs is configured via the `RSS_FEEDS` env var (comma-separated).

## Rationale

- **No new API key.** Phase 1's zero-cash rule (rule 05) prefers anything that doesn't require a new account, key issuance, or quota tracking.
- **No quota anxiety.** NewsAPI's free 100/day cap means the workflow has to count its own usage; RSS doesn't.
- **Real-time.** NewsAPI's free tier delays articles by 24 hours, which destroys the "morning brief" premise.
- **Publisher-agnostic.** Every reasonable publisher offers RSS. Custom curation (HN, Lobste.rs, niche newsletters) is one feed URL away.
- **Demo signal.** "Pulls from RSS feeds" is a phrase that reads as competent and free; "uses NewsAPI on the free tier" reads as a tutorial.

## Consequences

- **Positive**: see rationale.
- **Negative**: AutoStream owns the dedup logic — store `guid` (or fallback `link+pubDate` hash) in `content_briefs.guid` and filter against last 7 days. Workflow 2 implements this.
- **Negative**: feed-format edge cases (Atom vs RSS 2.0 vs RSS 1.0 vs broken feeds). n8n's RSS Feed Read node handles the first three; the last is caught by rule 03's bounded retry + skip-feed-continue-brief pattern.

## Reconsideration triggers

- A specific publisher of interest doesn't offer RSS and is only available via NewsAPI. (Unlikely — most premium publishers do offer RSS.)
- Phase 2 needs structured fields (author, category taxonomy, etc.) that RSS doesn't reliably provide. At that point, NewsAPI joins as a *supplemental* source, not a replacement.

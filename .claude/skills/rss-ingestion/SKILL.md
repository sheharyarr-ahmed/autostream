---
name: rss-ingestion
description: Use when configuring or debugging RSS feed reads in workflow 2 (daily content brief) — feed parsing, GUID dedup, freshness window, fan-out across multiple feeds. Triggers on rss, feed, content brief, atom.
tier: 1
---

Skill metadata only. Load `core.md` for the canonical fan-out + dedup pattern.

## Quick references

- Canonical fan-out + dedup: `core.md`
- ADR: `.claude/decisions/0004-rss-over-newsapi.md`
- Edge cases (Atom vs RSS variants): `.claude/skills/n8n-workflow-design/reference/node-catalog.md`

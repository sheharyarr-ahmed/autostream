---
name: imap-polling
description: Use when configuring or debugging IMAP email polling in workflow 3 (email classification) — polling cadence, UNSEEN flag, mark-as-seen after success, TLS handling. Triggers on imap, email, inbox, mailbox.
tier: 1
---

Skill metadata only. Load `core.md` for the canonical IMAP node config + mark-as-seen pattern.

## Quick references

- IMAP node config + mark-on-success: `core.md`
- TLS cert error remediation: `docs/TROUBLESHOOTING.md`
- ADR: `.claude/decisions/0005-imap-over-gmail-pubsub.md`

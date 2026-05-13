---
name: slack-notifications
description: Use when posting to Slack from AutoStream workflows — incoming webhook URLs, Block Kit templates for success/error notifications. Triggers on keywords like slack, alert, notify, channel.
tier: 1
---

Skill metadata only. Load `core.md` for Block Kit templates and the success/error patterns AutoStream uses.

## Quick references

- Block Kit templates: `core.md`
- Slack webhook rate-limit handling: `docs/TROUBLESHOOTING.md`
- Security: `.claude/rules/04-security.md` (treat webhook URL as a secret)

---
name: anthropic-claude-integration
description: Use when integrating Anthropic Claude calls into AutoStream workflows — model selection (Haiku/Opus), structured output with Zod-equivalent validation, prompt caching, token accounting. Triggers on keywords like Claude, anthropic, prompt, Haiku, Opus, JSON output.
tier: 1
---

Skill metadata only. Load `core.md` for hot-path patterns; `reference/model-spec.md` for the full model catalog and pricing reference.

## Quick references

- Hot-path templates (HTTP body, validation Function node): `core.md`
- Model spec + pricing table: `reference/model-spec.md`
- Tiering rule: `.claude/decisions/0006-haiku-vs-opus-model-tiering.md`
- Validation rule: `.claude/decisions/0008-zod-validation-llm-outputs.md`
- Prompt design discipline: `.claude/agents/claude-prompt-engineer.md`

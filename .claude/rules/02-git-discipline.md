# Rule 02 — Git Discipline

Single-author, attribution-free, conventional-commit history. The git log is part of the portfolio surface.

## Author

All commits authored by **Sheharyar Ahmed** (`sheharyar.softwareengineer@gmail.com`). Set locally:

```bash
git config --local user.name "Sheharyar Ahmed"
git config --local user.email "sheharyar.softwareengineer@gmail.com"
```

Never set this globally. Other projects on the same machine may have different authorship.

## Forbidden tokens in commit messages (blocked by `.githooks/commit-msg`)

Case-insensitive grep — any of these in a commit message blocks the commit:

- `claude`
- `claude.ai`
- `generated with`
- `co-authored-by`
- `ai-assisted`
- `🤖`

This applies to subject lines AND bodies. If a commit references the product name in passing, rephrase to avoid the token (e.g., "PreToolUse hook" instead of "Claude Code PreToolUse hook"). The hook is intentionally blunt.

The hook also has a second-layer defense via `.claude/settings.json`: a `PreToolUse` hook that blocks any `git commit --no-verify` or `--no-gpg-sign` invocation from the Bash tool, so the commit-msg hook can't be silently bypassed.

## Activation

The hook is not active by default after `git clone` — Git requires opt-in:

```bash
git config --local core.hooksPath .githooks
```

This is documented in the README quickstart so every contributor (i.e., Sheharyar on a new machine) activates it.

## Conventional commits

Subject format: `<type>: <imperative description>`

Allowed types: `chore`, `docs`, `build`, `feat`, `fix`, `refactor`, `rules`, `decisions`, `agents`, `skills`, `scaffold`.

- **Imperative mood**: "add docker-compose" not "added" or "adds."
- **Lowercase after the colon**.
- **No trailing period**.
- Body (optional) explains *why* the change is being made, not what — the diff shows the what.

## Forbidden git operations

- `git commit --amend` on pushed commits (rewrites history). Always create a new commit.
- `git push --force` to `main`. Branch-protect on the remote should also enforce this.
- `git rebase -i` (interactive rebase requires terminal interaction; use one-shot rebases or new commits instead).
- `git commit --no-verify` — blocked by `.claude/settings.json` PreToolUse hook AND by Sheharyar's own discipline.
- `git config --global` anything for this project. Always `--local`.

## Verification (run before any push)

```bash
# 1. Single author across all commits
git log --format='%an' | sort -u
# expected: "Sheharyar Ahmed" (one line)

# 2. No forbidden tokens anywhere
git log --all -p | grep -iE 'claude|generated|co-authored|ai-assisted|🤖' || echo "clean"

# 3. All subjects match conventional format
git log --format='%s' | grep -vE '^(chore|docs|build|feat|fix|refactor|rules|decisions|agents|skills|scaffold): ' || echo "all conventional"
```

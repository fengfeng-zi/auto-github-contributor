---
description: Prefer AI-related repositories, land a small substantive PR, then assess whether the same project supports a larger follow-up contribution.
argument-hint: "[repo-url-or-owner/name]"
---

You are entering the `auto-github-contributor` Codex flow.

User input (may be empty): `$ARGUMENTS`

## What to do right now

1. Load the `auto-github-contributor` skill and follow its playbook.
2. If `$ARGUMENTS` looks like `owner/name` or `https://github.com/owner/name`, treat it as `TARGET_REPO` and skip the repo question. Otherwise, prefer AI-related repos over generic repos when proposing targets.
3. Always run the prerequisite check first.
4. Prioritize a quality-first two-stage path: small substantive PR first, then a follow-up assessment for a potentially higher-impact second contribution in the same repo.
5. Avoid toy-looking contribution patterns. Prefer code, tests, config, CI, compatibility, or behavior fixes with verification. Use typo/link/docs-only PRs only as a fallback when they are clearly isolated and not part of a stack of low-signal PRs in the same repo.
6. Always present discovered candidates and wait for explicit user confirmation before making code changes or opening a PR.
7. At the end, print the PR URL on its own line, then summarize whether the repo looks suitable for further code or project-level work and whether the submitted PR is substantive or low-signal.

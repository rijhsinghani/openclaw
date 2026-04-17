---
name: github
description: "Read-only GitHub operations via `gh` CLI: view PRs/issues/runs, check CI status, query API. This override REMOVES pr create/merge/close and push commands — Ranveer MUST use ship.sh for all write operations. Use when: checking PR status or CI, viewing run logs, querying repo data. NOT for: creating/merging PRs (that is ship.sh's job)."
metadata:
  {
    "openclaw":
      {
        "emoji": "🐙",
        "requires": { "bins": ["gh"] },
      },
  }
---

# GitHub Skill (read-only override for ranveer / Ranveer)

This is a **workspace-level override** of the bundled OpenClaw github skill. It exists because Ranveer auto-merged PR #61 ~12s before CodeRabbit review on 2026-04-12 by invoking `gh pr merge` directly. The bundled github skill taught that command pattern, which made the bypass available.

**Hard rule:** Ranveer never runs `gh pr create`, `gh pr merge`, `gh pr close` (except for his own failed test PRs with explicit Sameer permission), `git push`, or any git history rewrite. The ONLY sanctioned write path is `ship.sh`.

## Allowed Commands (read-only)

### Pull Requests — view/check only

```bash
gh pr list --repo owner/repo
gh pr view 55 --repo owner/repo
gh pr checks 55 --repo owner/repo
gh pr diff 55 --repo owner/repo
gh pr status --repo owner/repo
```

### Issues — view/list only

```bash
gh issue list --repo owner/repo --state open
gh issue view 42 --repo owner/repo
```

Creating/closing issues is allowed when Sameer asks for it explicitly. Default is read-only.

### CI / Workflow Runs

```bash
gh run list --repo owner/repo --limit 10
gh run view <run-id> --repo owner/repo
gh run view <run-id> --repo owner/repo --log-failed
```

Re-running workflows (`gh run rerun`) is allowed — it's idempotent and doesn't write new code.

### API queries

```bash
gh api repos/owner/repo --jq '.stargazers_count'
gh api repos/owner/repo/pulls/55 --jq '.title, .state, .mergeable'
gh api repos/owner/repo/labels --jq '.[].name'
```

## FORBIDDEN Commands (all require ship.sh)

Do NOT run any of these. If you find yourself about to, STOP and invoke ship.sh instead:

- `gh pr create ...` — ship.sh creates the PR
- `gh pr merge ...` — ship.sh merges after CodeRabbit clean
- `gh pr close ...` — only Sameer closes PRs manually; exception only for Ranveer's own aborted test PRs after Sameer confirms
- `git push` / `git push origin <branch>` / `git push origin main` — ship.sh owns the push
- `git merge main` / `git merge origin/main` — no local main merges
- Any `gh api --method POST/PATCH/DELETE` against `/pulls` or `/merges`

## Why this override exists

2026-04-12 incident: Ranveer created PR #61 in `studio-os`, then ~12s later invoked `gh pr merge 61 --squash` before CodeRabbit had posted a review. The bundled github skill documented both `gh pr create` and `gh pr merge` as standard operations. This override strips those examples and replaces them with the hard rule above. The enforcement is behavioral (skill-prompt level) because OpenClaw's exec allowlist model matches resolved binary paths, not argv subcommands — `/opt/homebrew/bin/gh pr view` and `/opt/homebrew/bin/gh pr merge` resolve to the same binary path.

Structural enforcement via `exec-approvals.json` `security: "allowlist"` is a future hardening step — it would require populating an allowlist of every binary ship.sh and Ranveer legitimately need, which is out of scope for this patch.

## Notes

- Always specify `--repo owner/repo` when not in a git directory
- Use `gh api --cache 1h` for repeated read queries
- If you need to write to GitHub, the answer is always "run ship.sh"

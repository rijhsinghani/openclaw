---
name: ship
description: "Ship code via ship.sh — the ONLY merge path. Invokes ~/.openclaw/agents/ranveer/scripts/ship.sh which owns push, PR creation, CodeRabbit polling, merge, audit, and Slack messaging. NEVER call gh pr create, gh pr merge, or git push directly."
metadata:
  openclaw:
    emoji: "🚀"
    requires:
      bins: ["bash", "gh", "jq"]
---

# Ship — The Only Merge Path

## Slack UX (HARD RULES — violating breaks the task)

- Every message ≤15 words. COUNT THEM.
- Never ask open-ended questions. Use interactive buttons.
- During a ship.sh run: say NOTHING except ship.sh's own milestones.
- Blockers: post ONE message + buttons for resolution.

## How to post buttons (copy-paste pattern)

OpenClaw's Slack channel already has `capabilities.interactiveReplies: true`. To render buttons or a select, embed a directive inline in your reply text — the gateway compiles it into Block Kit automatically. No special tool call.

```
Dirty tree. How to proceed? [[slack_buttons: Stash:stash, Abort:abort, Cancel:cancel]]
```

```
Which repo? [[slack_select: Pick repo | Booking:studio-os, Content:content-engine, Finance:investment-accounting]]
```

Rules: ≤15 words before the directive. Up to 5 button options (more -> use `slack_select`). Labels are user-facing; values are what come back on click. Callback values are opaque tokens — wait for the interaction event, don't ask again in prose.

**Hard rule:** `ship.sh` is the ONLY sanctioned way to push, open a PR, poll CodeRabbit, and merge. Never call `gh pr create`, `gh pr merge`, `git push origin main`, or any direct merge command. If you find yourself typing any of those, STOP and use ship.sh.

## Preconditions (you own these)

Before invoking ship.sh, you must have:

1. **Any non-trunk feature branch** checked out — never ship from `main` or `master`. The branch can be one you created (e.g., `ranveer/<type>/<slug>`) OR an existing branch from another agent or Sameer (e.g., `gsd/phase-109-photo-pipeline-enhancement`). **ship.sh handles BOTH cases** — it creates a fresh PR if none exists for the branch, or reuses an existing PR via the `pr_open` `reused_existing` path. Do NOT escalate to Sameer just because the PR was opened by someone else; ship.sh is the right tool for both new and existing PRs.
2. All edits committed via `git commit` — **do NOT run `git push` yourself**, ship.sh owns the push.
3. `run-ci` passed locally (typecheck + lint + tests green) — or the equivalent for the target repo.
4. **`--body-file` is OPTIONAL.** If omitted, ship.sh auto-generates a continuation body (suitable for re-shipping an existing PR after addressing CodeRabbit feedback). Provide a real body only when creating a brand-new PR for which you want a custom description.

## The Invocation

```bash
~/.openclaw/agents/ranveer/scripts/ship.sh \
  --repo <absolute-repo-path> \
  --branch <current-branch-name> \
  --title "<PR title>" \
  --slack-channel C0AM06M0JE8 \
  --slack-thread <current-thread-ts-or-none> \
  --task-slug <slug>
  # --body-file is optional — auto-generated if omitted
```

ship.sh handles: WIP check, `git push`, `gh pr create`, CodeRabbit poll loop (30s interval, 20min timeout), merge on approval, audit row per stage to `~/.openclaw/agents/ranveer/data/audit/ship-runs.jsonl`, and all Slack milestone messages (≤15 words each). You stay silent between "PR opened" and the final result — ship.sh owns milestone messaging.

## Exit Codes

| Exit | Meaning                         | Your next move                                                                                                                                                      |
| ---- | ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `0`  | Merged. CodeRabbit clean.       | Done. ship.sh already posted the merge line — do **not** post again.                                                                                                 |
| `10` | Preflight failed.               | STOP. Read last row of `~/.openclaw/agents/ranveer/data/audit/ship-runs.jsonl` for the reason. Wait for Sameer.                                                 |
| `11` | Push failed.                    | STOP. Same audit-log read. Wait for Sameer.                                                                                                                          |
| `12` | PR open failed or already gone. | STOP. Same audit-log read. Wait for Sameer.                                                                                                                          |
| `20` | CodeRabbit requested changes.   | STOP. ship.sh posted the summary + PR URL. Wait for `ranveer fix it` (address comments) or `ranveer go anyway` (Sameer merges manually — you still do NOT merge).    |
| `21` | CodeRabbit review timeout.      | STOP. ship.sh escalated. Wait for Sameer.                                                                                                                            |
| `22` | PR closed before review.        | STOP. Manual recovery needed. Wait for Sameer.                                                                                                                       |
| `30` | Merge call failed post-approve. | STOP. Same audit-log read. Wait for Sameer.                                                                                                                          |

## Banned Commands (NEVER call these in a ship flow)

- `gh pr create` — ship.sh creates the PR
- `gh pr merge` — ship.sh merges
- `git push` / `git push origin main` — ship.sh pushes
- `cr review` in a shell loop — ship.sh polls CodeRabbit
- Any direct merge tool — there is no other merge path

If any of these appear in your plan, replace the entire block with a single `ship.sh` invocation.

## Rules

- NEVER enable auto-merge — Sameer merges PRs (ship.sh handles the merge call only after CodeRabbit approves)
- NEVER use placeholder text in PR body (`<describe what was found>`, lorem, etc.)
- NEVER create a duplicate PR for the same branch — ship.sh handles dedupe
- NEVER post to Slack between "PR opened" and the final ship.sh result — ship.sh owns milestone messaging
- All Slack messages (ack, blocker, final) are ≤15 words. Details live on the PR page.

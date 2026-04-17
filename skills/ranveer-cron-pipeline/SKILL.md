---
name: ranveer-cron-pipeline
description: "Cron-triggered memo pipeline commands. When a message starts with 'CRON:', run the matching command EXACTLY — do not modify, summarize, or add commentary. Daily/weekly memo pipelines handle their own Slack delivery via post-memo.sh."
metadata:
  openclaw:
    emoji: "⏰"
    requires:
      bins: ["bash"]
---

# ranveer-cron-pipeline — CRON Command Routing

When you receive a message starting with `CRON:`, execute the matching command exactly. Report only the exit code.

| Trigger                       | Command                                                                                                    |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `CRON: daily-pipeline`        | `bash ~/.openclaw/agents/ranveer/scripts/run-decision-pipeline.sh --mode=daily`                            |
| `CRON: weekly-pipeline`       | `bash ~/.openclaw/agents/ranveer/scripts/run-decision-pipeline.sh --mode=weekly`                           |
| `CRON: weekly-branch-cleanup` | Run auto-merge + auto-delete sweep across all active repos (see procedure below)                           |

If the pipeline fails, post the error to #code. If it succeeds, the pipeline handles its own Slack delivery via `post-memo.sh` — do not re-post.

Do NOT add commentary, do NOT summarize, do NOT modify the command.

## CRON: weekly-branch-cleanup — Procedure

Run in order for each repo (`studio-os`, `content-engine`, `investment-accounting`):

**Step 1 — Auto-merge green PRs (Ranveer's own PRs that are CodeRabbit-approved):**
```bash
bash ~/.openclaw/agents/ranveer/scripts/auto-merge-green-prs.sh --repo <owner/repo>
```
- Exit 0: merged one or more PRs → log result to #code thread
- Exit 2: no eligible PRs → continue
- Exit 3: eligible PRs found but blocked by gates → log which gate blocked to #code thread

**Step 2 — Auto-delete merged branches (safe path only):**
```bash
bash ~/.openclaw/agents/ranveer/scripts/auto-delete-merged-branches.sh --repo <owner/repo>
```
- Exit 0: deleted one or more branches → log count to #code thread
- Exit 2: no stale merged branches found → continue
- Exit 3: rate limit reached → stop and note in thread

**Kill-switches (autonomy.json):**
- `autonomy.autoMerge.enabled: false` → skip Step 1 entirely
- `autonomy.autoDeleteBranches.enabled: false` → skip Step 2 entirely
- `autonomy.dryrun: true` → both scripts run in dry-run mode (no actual merges or deletes)

**Post to #code after all repos:** one thread reply with counts:
> "Branch cleanup: merged N PRs, deleted M stale branches across 3 repos."
> If any gate blocked: "Note: X PRs blocked (reason). Review: [PR list]."

**Unmerged stale branches are NOT auto-deleted.** Surface them as a proposal only:
> "Found X unmerged branches older than 7 days in [repo]: [list]. Merge or delete?"

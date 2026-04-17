---
name: cr-loop
description: "Poll CodeRabbit review status on a PR until the review completes (approved, changes-requested, or timeout). Use when a PR has just been pushed and you need to wait for CodeRabbit's verdict before merging. Prefer this over hand-written polling loops. ship.sh already calls this internally — invoke cr-loop directly only when reviewing an existing PR that ship.sh didn't open."
metadata:
  openclaw:
    emoji: "🐰"
    requires:
      bins: ["gh", "jq"]
---

# cr-loop — CodeRabbit Review Polling

Wait for CodeRabbit (`coderabbitai[bot]` / `coderabbit[bot]` / `coderabbitai`) to finish reviewing a PR. Returns one of three outcomes: approved, changes-requested, or timeout.

## When to use

- A PR exists and you've pushed commits to it
- You need to know CodeRabbit's verdict before deciding what to do next
- You are NOT currently running ship.sh (ship.sh has its own internal poll loop — don't double-poll)

## When NOT to use

- Inside a ship.sh run — ship.sh owns polling
- For non-CodeRabbit reviewers — this skill is CR-specific
- If the PR hasn't been pushed yet — push first

## Invocation

```bash
gh pr view <PR_NUMBER> --repo <OWNER/REPO> --json reviews,statusCheckRollup 2>/dev/null
```

Poll every 30 seconds for up to 40 minutes (80 iterations max). On each iteration:

1. Fetch PR review state:
   ```bash
   gh pr view <PR_NUMBER> --repo <OWNER/REPO> --json reviews --jq '[.reviews[] | select(.author.login | test("coderabbit"; "i"))] | sort_by(.submittedAt) | last'
   ```
2. Check the `state` field of the latest CodeRabbit review:
   - `APPROVED` → exit 0 (success)
   - `CHANGES_REQUESTED` → exit 20 (needs fixes)
   - `COMMENTED` → still in progress, continue polling
   - null/missing → CR hasn't reviewed yet, continue polling
3. Check for stall signals: if review body contains `"Come back again in a few minutes"` → continue polling
4. After 20 minutes without a terminal state → exit 21 (timeout)

## Exit codes

| Exit | Meaning                       | Next move                                                                     |
| ---- | ----------------------------- | ----------------------------------------------------------------------------- |
| `0`  | CodeRabbit approved.          | Safe to merge. Use `ship.sh` or `gh pr merge` per repo policy.                |
| `20` | CodeRabbit requested changes. | Fetch comments with `cr-check-pr` or `cr-autofix`. Do NOT merge.              |
| `21` | Polling timed out (40 min).   | Post a Slack line to #code; wait for Sameer or retry after manual CR kick.    |
| `22` | PR closed/merged/unreachable. | Manual recovery; inspect PR state.                                            |

## One-shot helper

Drop this into a script when you need inline polling:

```bash
poll_coderabbit() {
  local pr_number="$1"
  local repo="$2"
  local max_iters="${3:-80}"
  local sleep_s="${4:-30}"

  for i in $(seq 1 "$max_iters"); do
    local review
    review="$(gh pr view "$pr_number" --repo "$repo" --json reviews \
      --jq '[.reviews[] | select(.author.login | test("coderabbit"; "i"))] | sort_by(.submittedAt) | last // {}')"
    local state
    state="$(echo "$review" | jq -r '.state // empty')"
    case "$state" in
      APPROVED)           echo "approved"; return 0 ;;
      CHANGES_REQUESTED)  echo "changes_requested"; return 20 ;;
    esac
    sleep "$sleep_s"
  done
  echo "timeout"; return 21
}
```

## Slack protocol

During polling, post NOTHING. ship.sh owns milestone messaging when it's running; outside of ship.sh, post exactly one final line after the loop resolves:

- Approved: `CodeRabbit approved PR #<N>. Ready to merge.`
- Changes: `CodeRabbit requested changes on PR #<N>. <short summary>.`
- Timeout: `CodeRabbit review timed out on PR #<N>. Escalating.`

Each message ≤15 words.

## Rules

- NEVER merge based on CR silence — absence of `CHANGES_REQUESTED` is not approval.
- NEVER shorten the timeout below 10 minutes — CodeRabbit can take 5–8 minutes on large diffs.
- NEVER poll more aggressively than every 30s — you'll hit GitHub rate limits.
- If `gh` returns a 404 on the PR, treat as exit 22 and stop.

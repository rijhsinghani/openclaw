---
name: cr-check-pr
description: "Inspect CodeRabbit review comments on an open PR — read-only. Lists all unresolved CodeRabbit threads with severity, file path, line number, and the agent prompt (if any). Use when you want to understand what CR flagged before deciding to autofix, hand-edit, or defer. Does NOT modify any files."
metadata:
  openclaw:
    emoji: "🔍"
    requires:
      bins: ["gh", "jq"]
---

# cr-check-pr — Read CodeRabbit Review Comments

Read-only inspection of CodeRabbit's review on a PR. Returns a structured summary grouped by severity. Use this before deciding between `cr-autofix`, manual editing, or deferring the review.

## When to use

- You saw CodeRabbit requested changes and want to understand scope
- Before invoking `cr-autofix` — use this to preview what will be changed
- To audit CodeRabbit's quality on a specific PR (is it flagging real issues or nits?)
- To produce a human-readable summary for Slack before acting

## When NOT to use

- If you want to ACT on the comments — use `cr-autofix`
- If CodeRabbit hasn't reviewed yet — use `cr-loop`

## Invocation

```bash
PR_NUMBER="${1:-$(gh pr view --json number --jq '.number')}"
REPO="${2:-$(gh repo view --json nameWithOwner --jq '.nameWithOwner')}"
```

### Fetch threads

```bash
gh api graphql -f query='
query($owner: String!, $name: String!, $num: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $num) {
      title
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          comments(first: 10) {
            nodes { author { login } body path line createdAt }
          }
        }
      }
      reviews(first: 20) {
        nodes { author { login } state body submittedAt }
      }
    }
  }
}' -F owner="${REPO%%/*}" -F name="${REPO##*/}" -F num="$PR_NUMBER"
```

### Filter to CodeRabbit threads only

```bash
| jq '.data.repository.pullRequest as $pr
      | { title: $pr.title,
          latestReview: ($pr.reviews.nodes
             | map(select(.author.login | test("coderabbit"; "i")))
             | sort_by(.submittedAt) | last),
          unresolvedThreads: ($pr.reviewThreads.nodes
             | map(select(.isResolved == false))
             | map(select(.comments.nodes[0].author.login | test("coderabbit"; "i")))
             | map({
                 id: .id,
                 path: .comments.nodes[0].path,
                 line: .comments.nodes[0].line,
                 body: .comments.nodes[0].body,
               }))
        }'
```

## Parse each comment body

For each thread body, extract:

1. **Header**: `_(Type)_ \| _(Severity)_` (e.g., `_Bug_ | _Critical_`)
2. **Description**: the main text block
3. **Agent prompt**: content inside `<details><summary>🤖 Prompt for AI Agents</summary>...</details>`
4. **Location**: path + line from the GraphQL response

Map severity:

| CR label              | Priority     |
| --------------------- | ------------ |
| Critical / High       | 🔴 CRITICAL  |
| Security              | 🔒 SECURITY  |
| Medium                | 🟠 HIGH      |
| Minor / Low / Nitpick | 🟡 MEDIUM    |
| Info / Suggestion     | 🟢 LOW       |

## Output format

Return a structured summary. If outputting to Slack, use this layout (ONE message ≤600 chars):

```
PR #<N> "<title>" — CodeRabbit: <APPROVED|CHANGES_REQUESTED|COMMENTED>

🔴 <count> critical | 🟠 <count> high | 🟡 <count> medium | 🟢 <count> low

Top 3 issues:
1. [CRITICAL] <path>:<line> — <1-line summary>
2. [HIGH] <path>:<line> — <1-line summary>
3. [MEDIUM] <path>:<line> — <1-line summary>

Next move: [[slack_buttons: Auto-fix:cr-autofix, Review manually:review, Defer:defer]]
```

If outputting to local terminal / session log, use a full table:

```
# | Sev    | Type      | Location              | Summary
--+--------+-----------+-----------------------+--------------------
1 | 🔴 CRIT | Bug      | src/auth/svc.py:42    | Authorization inverted
2 | 🟠 HIGH | Bug      | src/db/repo.py:89     | Missing await
3 | 🟡 MED  | Nitpick  | src/utils.py:12       | Unused import
```

## Return values

Exit 0: parsed successfully (even if 0 threads — that's a valid state).
Exit 1: pre-flight failed (no PR, auth fail, graphql error).
Exit 2: PR exists but CodeRabbit has not reviewed yet (hint user to run `cr-loop`).

## Rules

- READ-ONLY. Never apply fixes. Never `git commit`. Never `gh pr comment`.
- Don't collapse multiple CR reviews — always report the latest one.
- Cap Slack output at 3 representative issues. For full list, write to a local file and print the path.
- If a thread has no agent prompt, note it with `[no auto-fix available]` — signals human review needed.

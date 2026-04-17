---
name: cr-autofix
description: "Auto-apply CodeRabbit review suggestions on an open PR. Fetches unresolved CodeRabbit comments via `gh api graphql`, runs each comment's '🤖 Prompt for AI Agents' instruction, applies the edits, commits once, and pushes. Use when CodeRabbit returned CHANGES_REQUESTED and the comments have actionable agent prompts. Safer alternative to hand-editing files based on CR output."
metadata:
  openclaw:
    emoji: "🤖"
    requires:
      bins: ["gh", "jq", "git"]
---

# cr-autofix — Apply CodeRabbit Suggestions Automatically

Fetch all unresolved CodeRabbit review threads on the current branch's PR and apply their fix suggestions in one consolidated commit. Fails closed: if any suggestion is ambiguous or conflicts, skip it and continue with the rest.

## When to use

- CodeRabbit returned `CHANGES_REQUESTED` (cr-loop exit 20) or you're manually invoking after reviewing comments
- The PR branch is still checked out locally
- You haven't already made manual edits addressing these comments (avoid double-fixing)

## When NOT to use

- Comments are discussions/questions, not fix suggestions (those need human judgment)
- CodeRabbit hasn't reviewed yet (run `cr-loop` first)
- You're on `main` — branch out first
- Auth/payment/webhook/migration files in the diff — route to Sameer, don't autofix

## Prerequisites

```bash
gh auth status                 # must succeed
git branch --show-current      # must NOT be main/master
git status --porcelain         # must be clean (no uncommitted local edits)
```

## Workflow

### Step 1 — Identify PR

```bash
PR_NUMBER="$(gh pr view --json number --jq '.number')"
REPO="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
```

If no PR: STOP. Tell user `No PR for this branch; push and open one first.`

### Step 2 — Fetch unresolved CodeRabbit threads

```bash
gh api graphql -f query='
query($owner: String!, $name: String!, $num: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $num) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          comments(first: 10) {
            nodes { author { login } body path line }
          }
        }
      }
    }
  }
}' -F owner="${REPO%%/*}" -F name="${REPO##*/}" -F num="$PR_NUMBER" \
  | jq '.data.repository.pullRequest.reviewThreads.nodes
         | map(select(.isResolved == false))
         | map(select(.comments.nodes[0].author.login
               | test("coderabbit"; "i")))'
```

Filter to threads started by `coderabbitai[bot]` / `coderabbit[bot]` / `coderabbitai`.

### Step 3 — Parse each comment

For each thread's root comment body, extract:

1. **Severity** from header pattern `_([^_]+)_ \| _([^_]+)_`
2. **Description** (main body text)
3. **Agent prompt** from the `<details><summary>🤖 Prompt for AI Agents</summary>...</details>` block
4. **Location** (`path` + `line` from the comment metadata)

Severity mapping:
- `Critical` / `High` / `Security` → apply (high priority)
- `Medium` → apply
- `Minor` / `Low` / `Nitpick` → apply if the fix is <5 lines; otherwise defer
- `Info` / `Suggestion` — defer unless the agent prompt is trivially mechanical

### Step 4 — Apply fixes

For each thread with an extracted agent prompt:

1. Read the target file at the location
2. Execute the agent prompt as a direct instruction — produce the edit
3. Apply it with the Edit tool (in-repo file)
4. Track the file path in a CHANGED_FILES list

If a fix fails (ambiguous prompt, file not found, line out of range): log `skipped: <thread_id> — <reason>` and continue.

### Step 5 — Commit + push

If CHANGED_FILES is non-empty:

```bash
git add ${CHANGED_FILES[@]}
git commit -m "fix: apply CodeRabbit autofix suggestions for PR #$PR_NUMBER

Co-Authored-By: CodeRabbit <coderabbit@pullrequest.com>"
git push
```

One commit total, regardless of how many threads were fixed.

### Step 6 — Post summary to PR

```bash
gh pr comment "$PR_NUMBER" --body "$(cat <<EOF
## CodeRabbit Autofix Applied

Fixed ${#CHANGED_FILES[@]} file(s) from N unresolved thread(s). Skipped: M (see branch history).

**Files modified:**
$(printf -- '- \`%s\`\n' "${CHANGED_FILES[@]}")

The latest autofix changes are on the \`$(git branch --show-current)\` branch.
EOF
)"
```

### Step 7 — Slack milestone

Post exactly one line to #code:
- Applied: `Auto-fixed N CodeRabbit comments on PR #<N>. Re-review triggered.`
- Partial: `Fixed N, skipped M (ambiguous). Pushed. Check PR.`
- None applicable: `No auto-fixable CodeRabbit comments on PR #<N>.`

## Safety rules

- NEVER commit `.env`, secrets, credentials, or large binaries
- NEVER auto-apply a comment that asks to rewrite auth / payment / webhook / migration logic (flag for human review)
- NEVER force-push; a regular `git push` is correct (branch is ahead)
- If the agent prompt includes shell commands to run, execute them ONLY if they're read-only (checks, tests). Never run destructive ones unprompted.
- If the overall set of changes exceeds 200 lines, pause and report count — let Sameer approve before pushing

## Exit codes

| Exit | Meaning                                        |
| ---- | ---------------------------------------------- |
| `0`  | Applied all fixes, pushed, posted PR comment.  |
| `1`  | Pre-flight failed (no PR, dirty tree, on main) |
| `2`  | No CodeRabbit comments to apply.               |
| `3`  | Some fixes applied; some skipped (see log).    |
| `10` | Push failed after commit.                      |

---
name: cr-escalation-loop
description: "Outer CodeRabbit autofix loop with model escalation. Replaces the flat cr-loop→cr-autofix→cr-loop chain. Manages round counting, tier selection (Codex→Sonnet→Opus→abandon), autonomy.json kill-switch, daily escalation cap, and state persistence per PR. Invoke this instead of calling cr-autofix directly after a ship.sh exit 20."
metadata:
  openclaw:
    emoji: "🪜"
    requires:
      bins: ["bash", "gh", "jq", "git"]
---

# cr-escalation-loop — CodeRabbit Autofix with Model Escalation

When CodeRabbit returns `CHANGES_REQUESTED` after a PR push, do NOT call `cr-autofix` directly. Instead, invoke this skill. It manages an escalation ladder so stuck PRs are resolved by progressively stronger models rather than looping forever or pinging Sameer.

## Kill-switch check (ALWAYS FIRST)

Before doing anything, read `autonomy.json`:

```bash
AUTONOMY_FILE="$HOME/.openclaw/agents/ranveer/autonomy.json"
CR_ESC_ENABLED=$(jq -r '.crEscalation.enabled // true' "$AUTONOMY_FILE" 2>/dev/null)
```

If `crEscalation.enabled` is `false`:
- Stop here. Do NOT run any escalation.
- Post to #code: `CR escalation disabled via autonomy.json. PR #<N> needs manual review.`
- Exit with the original ship.sh exit 20 behavior (leave PR open, no merge).

## Escalation config (from autonomy.json)

```bash
MAX_ROUNDS=$(jq -r '.crEscalation.maxRoundsPerPR // 4' "$AUTONOMY_FILE")
MAX_ESC_PER_DAY=$(jq -r '.crEscalation.maxEscalationsPerDay // 3' "$AUTONOMY_FILE")
T1_MODEL=$(jq -r '.crEscalation.tierModels.t1 // "codex-gpt-5.4"' "$AUTONOMY_FILE")
T2_MODEL=$(jq -r '.crEscalation.tierModels.t2 // "claude-sonnet-4-6"' "$AUTONOMY_FILE")
T3_MODEL=$(jq -r '.crEscalation.tierModels.t3 // "claude-opus-4-7"' "$AUTONOMY_FILE")
```

## State management

Per-PR round state is tracked at:
```
~/.openclaw/agents/ranveer/data/state/cr-rounds/<owner>-<repo>-<pr>.json
```

Use `cr-escalation-state.sh` to read/write state (never edit the JSON directly):

```bash
STATE_SCRIPT="$HOME/.openclaw/agents/ranveer/scripts/cr-escalation-state.sh"

# Read current round count
ROUNDS=$(bash "$STATE_SCRIPT" rounds "<owner/repo>" "<pr>")

# Append a completed round
bash "$STATE_SCRIPT" append "<owner/repo>" "<pr>" "<round_num>" "<model>" "<cr_state_after>"

# Wipe on approve or close
bash "$STATE_SCRIPT" wipe "<owner/repo>" "<pr>"
```

## Tier selection

| Round | Tier | Model            | Who proposes the fix? |
|-------|------|------------------|-----------------------|
| 1     | T1   | codex-gpt-5.4    | Codex (cr-autofix skill as-is) |
| 2     | T1   | codex-gpt-5.4    | Codex (cr-autofix skill as-is) |
| 3     | T2   | claude-sonnet-4-6 | Sonnet via dispatch-litellm.sh --mode pr-autofix |
| 4     | T3   | claude-opus-4-7  | Opus via dispatch-litellm.sh --mode pr-autofix |
| 5+    | T4   | —                | Abandon (close PR, log, done) |

"Round" = number of fix attempts completed so far (rounds already in state file + 1 for current).

## Full procedure

### Entry point

This skill is invoked after `ship.sh` exits 20 (CodeRabbit requested changes). You must already have:
- `PR_NUMBER` — the PR number
- `REPO` — owner/repo string (e.g. `samrijh/studio-os`)
- `BRANCH` — the branch name

### Step 1 — Determine current round

```bash
ROUNDS_DONE=$(bash "$STATE_SCRIPT" rounds "$REPO" "$PR_NUMBER")
THIS_ROUND=$(( ROUNDS_DONE + 1 ))
```

If `THIS_ROUND > MAX_ROUNDS` (i.e. > 4), jump directly to **Tier 4 — Abandon**.

### Step 2 — 30-minute wall-clock guard

Record start time at skill entry. If this round's total elapsed time (polling + fix + push) exceeds 30 minutes, abandon early:

```bash
ROUND_START_EPOCH=$(date +%s)
# ... after any blocking step:
ELAPSED=$(( $(date +%s) - ROUND_START_EPOCH ))
if (( ELAPSED > 1800 )); then
  # jump to abandon
fi
```

### Step 3 — Select tier and run fix

**Tier 1 (rounds 1–2): Codex via cr-autofix**

Invoke the `cr-autofix` skill exactly as before. Codex applies the CR suggestions and pushes.

After Codex pushes, poll for the new CR verdict using the `cr-loop` skill (40-minute cap, 80 iterations at 30s each). On verdict:
- `APPROVED` → wipe state, merge via ship.sh, done.
- `CHANGES_REQUESTED` → append round to state, continue to next round.
- Timeout/closed → append round, jump to Tier 4.

**Tier 2 (round 3): Sonnet via dispatch-litellm.sh --mode pr-autofix**

1. Fetch all unresolved CR comments into a temp file:
   ```bash
   CR_COMMENTS_FILE=$(mktemp -t cr-comments-XXXXXX.txt)
   gh api graphql -f query='
   query($owner: String!, $name: String!, $num: Int!) {
     repository(owner: $owner, name: $name) {
       pullRequest(number: $num) {
         reviewThreads(first: 100) {
           nodes {
             isResolved
             comments(first: 5) {
               nodes { author { login } body path line }
             }
           }
         }
       }
     }
   }' -F owner="${REPO%%/*}" -F name="${REPO##*/}" -F num="$PR_NUMBER" \
     | jq -r '.data.repository.pullRequest.reviewThreads.nodes
       | map(select(.isResolved == false))
       | map(select(.comments.nodes[0].author.login | test("coderabbit"; "i")))
       | .[] | .comments.nodes[0].body' > "$CR_COMMENTS_FILE"
   ```

2. Fetch current diff:
   ```bash
   DIFF_FILE=$(mktemp -t cr-diff-XXXXXX.diff)
   gh pr diff "$PR_NUMBER" --repo "$REPO" > "$DIFF_FILE"
   ```

3. Call dispatch-litellm.sh:
   ```bash
   LITELLM_SCRIPT="$HOME/.openclaw/agents/ranveer/scripts/dispatch-litellm.sh"
   APPROACH_JSON=$(bash "$LITELLM_SCRIPT" \
     --mode pr-autofix \
     --pr "$PR_NUMBER" \
     --repo "$REPO" \
     --round "$THIS_ROUND" \
     --model "$T2_MODEL" \
     --cr-comments-file "$CR_COMMENTS_FILE" \
     --diff-file "$DIFF_FILE")
   LITELLM_RC=$?
   ```

   If `LITELLM_RC` is non-zero (cap reached, error): treat as Tier 1 retry failure → jump to Tier 3 if round < 4, else Tier 4.

4. Extract approach and dispatch to Codex (Codex is the ONLY writer of code):
   ```bash
   APPROACH=$(echo "$APPROACH_JSON" | jq -r '.approach')
   FILES=$(echo "$APPROACH_JSON" | jq -r '.files_to_edit[]')
   DIFF_STRATEGY=$(echo "$APPROACH_JSON" | jq -r '.diff_strategy')
   ABANDON=$(echo "$APPROACH_JSON" | jq -r '.abandon_recommended // false')
   ```

   If `ABANDON == "true"` AND `THIS_ROUND >= 3`: jump to **Tier 4 — Abandon**.

   Otherwise, build a Codex task spec incorporating the approach and dispatch it using the `ranveer-task-spec` skill. Sonnet's `diff_strategy` becomes the task's `description`.

5. After Codex applies the fix and pushes, poll for CR verdict using `cr-loop` (40-min cap).
   - `APPROVED` → wipe state, merge.
   - `CHANGES_REQUESTED` → append round to state, continue.

**Tier 3 (round 4): Opus via dispatch-litellm.sh --mode pr-autofix**

Same as Tier 2 but:
- Model: `$T3_MODEL` (claude-opus-4-7)
- Include ALL prior round history in the CR comments file (read from state file and prepend a summary).
- Opus gets told: "You are performing a strategic reassessment. Rounds 1–3 all returned CHANGES_REQUESTED. Below is the full history..."

If Opus returns `abandon_recommended=true` OR if Codex fails to push a valid fix → jump to **Tier 4**.

After Codex applies Opus's approach:
- Poll for CR verdict (40-min cap).
- `APPROVED` → wipe state, merge.
- `CHANGES_REQUESTED` → Tier 4.

**Tier 4 — Abandon (round 5 or explicit abandon)**

Codex does NOT run. No more fix attempts. Silent graceful shutdown:

1. Fetch final PR URL:
   ```bash
   PR_URL=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json url --jq '.url')
   ```

2. Close PR and delete branch:
   ```bash
   gh pr close "$PR_NUMBER" --repo "$REPO" --comment "Abandoned after $THIS_ROUND escalation round(s). Autofix exhausted model ladder (Codex×2 → Sonnet → Opus). See audit log for details."
   gh api -X DELETE "repos/${REPO}/git/refs/heads/${BRANCH}" 2>/dev/null || true
   ```

3. Log to `data/audit/abandoned-prs.jsonl`:
   ```bash
   ABANDON_LOG="$HOME/.openclaw/agents/ranveer/data/audit/abandoned-prs.jsonl"
   FINAL_CR=$(gh api graphql ... | jq -r '...' )  # last CR comment body
   jq -cn \
     --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     --argjson pr "$PR_NUMBER" \
     --arg repo "$REPO" \
     --arg reason "exhausted_escalation_ladder" \
     --argjson rounds_tried "$THIS_ROUND" \
     --arg final_cr_comments "$FINAL_CR" \
     '{ts:$ts, pr:$pr, repo:$repo, reason:$reason, rounds_tried:$rounds_tried, final_cr_comments:$final_cr_comments}' \
     >> "$ABANDON_LOG"
   ```

4. Wipe state file:
   ```bash
   bash "$STATE_SCRIPT" wipe "$REPO" "$PR_NUMBER"
   ```

5. Do NOT post to Slack #code. Silent shutdown.

## Safety rails summary

| Rail | Behavior |
|------|----------|
| Hard cap 4 rounds | Round 5+ = Tier 4 abandon, no more fix attempts |
| 30-min wall clock | Abandon early if any single round exceeds 30 min |
| Daily escalation cap | dispatch-litellm.sh exits 1 with cap message; treat as Tier failure → advance or abandon |
| autonomy.json kill-switch | `crEscalation.enabled=false` → stop at exit 20, post to Slack |
| Codex-only writes code | NEVER apply file edits directly from this skill; always dispatch to Codex |
| Auth/payment guard | If CR comments or files match Tier-3 path regex, abort loop and post to #code for human review |

## Dry-run mode

If `autonomy.dryrun = true` in `openclaw.json`:
- Do NOT call dispatch-litellm.sh or cr-autofix.
- Log what WOULD have happened to state file with `cr_state_after="dry_run"`.
- Post to #code: `(dry-run) Would have escalated PR #<N> to <model> on round <N>.`

## Wiring: when to invoke this skill

This skill replaces the old behavior in `ranveer-autonomous-batch` where "CR iteration 3 reached → escalate to Sameer." The new rule:

> After any `ship.sh` exit 20 (CHANGES_REQUESTED), invoke **cr-escalation-loop** instead of stopping. The loop manages all subsequent rounds autonomously. Only if the loop itself aborts with an auth/payment guard violation should Sameer be notified.

The `ranveer-autonomous-batch` escape hatch "CR iteration 3 reached" is now replaced by Tier 4 abandon. The loop counts its own rounds — do not double-count with the old `maxCrIterations` field.

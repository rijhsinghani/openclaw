---
name: ranveer-consult-knowledge
description: "Task-time retrieval over Ranveer's knowledge notes. Given task keywords, returns the top 1-3 relevant knowledge notes (with first 30 lines inline) so Ranveer can cite established principles before dispatching multi-file work, touching auth/payment/security code, or planning a refactor. Pure shell + grep, no LLM call, sub-second. Call at the START of any non-trivial task."
metadata:
  openclaw:
    emoji: "📚"
    requires:
      bins: ["bash", "grep", "awk", "sort"]
---

# consult-knowledge

Ranveer files a lot of knowledge notes. Without retrieval they decay into
noise. This skill is the retrieval half of the learning loop: given task
keywords, surface the 1-3 most relevant notes so past lessons inform the
current plan.

## When to invoke

Run this skill at the **start** of any task matching:

- Multi-file work (3+ files)
- Auth / payment / Stripe / secrets / migrations (hard-gate paths)
- Anything the user classifies as "architectural" or "refactor"
- Any task whose description includes words in the curriculum domains
  (code review, testing, error handling, observability, CI/CD, etc.)

Skip for:

- Single-line typo fixes
- Pure status questions ("is the cron healthy?")
- Tasks already scoped to a specific file by Sameer

## Usage

```bash
Skill("consult-knowledge", "<space-separated keywords>")
```

Example:

```bash
Skill("consult-knowledge", "payment stripe error retry")
```

## How it works

**Step 0 (GBrain pre-step):** Run `~/.openclaw/agents/ranveer/scripts/gbrain-consult.sh "<keywords>"` first. This queries the SecondBrain vault (116 pages from `principle/` + `decision/`) using hybrid vector+keyword search. If it returns hits, include them as "Vault context:" in the plan artifact. If no hits (common without vector embeddings), fall through to Step 1.

1. **Tokenize** the input string into lowercase keywords (stop-words dropped).
2. **Grep** filenames + titles under
   `~/.openclaw/agents/ranveer/knowledge/` (recursive, includes `principle/`).
3. **Score** each note: filename hits +3, H1 title hits +2, body hits +1.
4. **Rank** and return the top 3. For each hit, emit path + first 30
   lines of content so Ranveer sees the principle inline without loading
   the full file into context.

## Shell implementation

Run this exact command, substituting `$KEYWORDS` for the skill argument:

```bash
bash -c '
  KB="/Users/sameerrijhsinghani/.openclaw/agents/ranveer/knowledge"
  KEYWORDS="$1"
  # Tokenize: lowercase, strip punctuation, split on whitespace, drop short tokens
  tokens=$(echo "$KEYWORDS" | tr "[:upper:]" "[:lower:]" \
    | tr -c "a-z0-9 " " " \
    | tr -s " " "\n" \
    | awk "length > 2 && !/^(the|and|for|with|from|into|this|that|has|how|why|when|not|are|will|was|can|but)\$/")

  if [ -z "$tokens" ]; then
    echo "consult-knowledge: no usable keywords in \"$KEYWORDS\""
    exit 0
  fi

  # Score each knowledge file
  tmpscore=$(mktemp)
  for f in $(find "$KB" -type f -name "*.md"); do
    score=0
    fname_lower=$(basename "$f" | tr "[:upper:]" "[:lower:]")
    # First H1 header, fallback to filename
    title=$(grep -m1 "^# " "$f" 2>/dev/null | sed "s/^# //" | tr "[:upper:]" "[:lower:]")
    body_lower=$(tr "[:upper:]" "[:lower:]" < "$f")
    for tok in $tokens; do
      case "$fname_lower" in *"$tok"*) score=$((score+3));; esac
      case "$title" in *"$tok"*) score=$((score+2));; esac
      # Body: count occurrences, cap at 5 to prevent one big file dominating
      occ=$(echo "$body_lower" | grep -o "$tok" | wc -l | tr -d " ")
      if [ "$occ" -gt 5 ]; then occ=5; fi
      score=$((score+occ))
    done
    if [ "$score" -gt 0 ]; then
      printf "%d\t%s\n" "$score" "$f" >> "$tmpscore"
    fi
  done

  if [ ! -s "$tmpscore" ]; then
    echo "consult-knowledge: no matching notes for \"$KEYWORDS\""
    rm -f "$tmpscore"
    exit 0
  fi

  echo "consult-knowledge: top matches for \"$KEYWORDS\""
  echo "----"
  sort -rn "$tmpscore" | head -3 | while IFS=$(printf "\t") read -r score path; do
    rel="${path#$KB/}"
    echo "## [$score] $rel"
    head -30 "$path"
    echo ""
    echo "---- (full note: $path)"
    echo ""
  done
  rm -f "$tmpscore"
' _ "$KEYWORDS_ARG"
```

## Output contract

- Stdout: human-readable block with top-3 matches, each preceded by a
  `## [<score>] <relative-path>` header and followed by the first 30
  lines of the note.
- Exit 0 on all paths (zero matches is informational, not an error).
- Never posts to Slack. Never writes files. Read-only.

## Post-consult behavior (what Ranveer does with the output)

1. If any returned principle is directly relevant, quote its title and
   one-line summary in the plan artifact (`ranveer-plan-*.md`) or in the
   task spec `description` field.
2. If the note says "never do X" and the task is about to do X, STOP and
   escalate to Sameer rather than dispatch.
3. If zero matches, proceed but log `consult_knowledge: no matches` in
   the plan artifact so the miss is visible for future curriculum
   prioritization.

## Why this exists

Before this skill, Ranveer filed knowledge notes weekly and almost never
read them back. The knowledge curve was flat. Retrieval at task-start
turns the notes into actively-used principles instead of filed-and-
forgotten reports. This is the "R" in the Formation-Evolution-Retrieval
loop from the 2025 agent memory surveys (arxiv 2512.13564, Mem^p 2508.06433).

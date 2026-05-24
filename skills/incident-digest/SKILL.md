---
name: incident-digest
description: 'Post-incident learning. Given a session id or ''last'', reads the transcript + dispatch logs, synthesizes what failed and why, and writes a durable principle note to ~/.openclaw/agents/ranveer/knowledge/principle/incident-<slug>-<date>.md using the When-to-apply / Principle / Evidence / Anti-pattern format. Also bumps the related curriculum domain priority in curriculum.yaml. Triggered by ranveer-watchdog on real failures or invoked on demand after an escalation. Use when summarizing incidents into a digest. Triggers include: ''incident digest'', ''summarize the incidents'', ''what broke this week'', ''incident summary''.'
metadata:
  openclaw:
    emoji: 🩺
    requires:
      bins:
      - bash
      - jq
      - awk
      - grep
      - date
      - python3
---

# incident-digest

Convert a failure into a durable principle. Without this, mistakes
recur because the lesson dies with the session.

## When to invoke

Two call sites:

1. **Automatic** — `ranveer-watchdog` plugin fires this skill when an
   agent run ends with `success: false` AND the failure is a real
   engineering mistake (not infra/lifecycle — see loopguards below).
2. **On demand** — Sameer or Ranveer runs
   `Skill("incident-digest", "<session-id-or-last>")` after an
   escalation, a reverted PR, or a regression.

## Usage

```bash
Skill("incident-digest", "<session-id>")
# or
Skill("incident-digest", "last")
```

## Loopguards (CRITICAL — do NOT remove)

Before doing anything, this skill checks:

1. **Recursion guard** — if the session being digested was itself
   running `incident-digest`, abort immediately (prevents digest-on-
   digest loops when the digest skill itself fails).
2. **Rate limit** — max 1 digest per 60 minutes. State kept at
   `~/.openclaw/agents/ranveer/data/state/incident-digest-last.txt`
   (ISO timestamp). If the last run was < 60 min ago, log
   `rate-limited` and exit 0.
3. **Noise filter** — skip failures whose error string matches these
   patterns (they are infra/lifecycle, not engineering lessons):
   - `quiet-hours`
   - `Agent couldn't generate a response`
   - `context window exhausted`
   - `rate_limit_exceeded`
   - `ECONNREFUSED`
   - durations < 60 seconds (fast aborts usually = transient)

If any guard trips, exit 0 without writing anything.

## Implementation

```bash
bash -c '
  SESSION_ARG="$1"
  KB_DIR="/Users/sameerrijhsinghani/.openclaw/agents/ranveer/knowledge/principle"
  STATE_DIR="/Users/sameerrijhsinghani/.openclaw/agents/ranveer/data/state"
  SESSIONS_DIR="/Users/sameerrijhsinghani/.openclaw/agents/ranveer/sessions"
  ABORT_LOG="/Users/sameerrijhsinghani/.openclaw/agents/ranveer/data/audit/abort-log.jsonl"
  CURRICULUM="/Users/sameerrijhsinghani/.openclaw/agents/ranveer/knowledge/curriculum.yaml"
  GUARD_FILE="$STATE_DIR/incident-digest-last.txt"
  mkdir -p "$STATE_DIR" "$KB_DIR"

  # Rate-limit check
  if [ -f "$GUARD_FILE" ]; then
    last_ts=$(cat "$GUARD_FILE" 2>/dev/null)
    if [ -n "$last_ts" ]; then
      now_epoch=$(date +%s)
      last_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$last_ts" +%s 2>/dev/null || echo 0)
      delta=$((now_epoch - last_epoch))
      if [ "$delta" -lt 3600 ]; then
        echo "incident-digest: rate-limited (last run ${delta}s ago, threshold 3600s)"
        exit 0
      fi
    fi
  fi

  # Resolve session id
  if [ "$SESSION_ARG" = "last" ] || [ -z "$SESSION_ARG" ]; then
    SESSION_ID=$(ls -t "$SESSIONS_DIR"/*.jsonl 2>/dev/null | head -1 | xargs -I {} basename {} .jsonl)
  else
    SESSION_ID="$SESSION_ARG"
  fi

  SESSION_FILE="$SESSIONS_DIR/$SESSION_ID.jsonl"
  if [ ! -f "$SESSION_FILE" ]; then
    echo "incident-digest: session file not found: $SESSION_FILE"
    exit 0
  fi

  # Recursion guard: skip if session was itself running incident-digest
  if grep -q "incident-digest" "$SESSION_FILE" 2>/dev/null; then
    echo "incident-digest: recursion guard — session was itself running incident-digest"
    exit 0
  fi

  # Pull the latest abort row for this session (if any)
  ABORT_ROW=$(grep -F "\"sessionId\":\"$SESSION_ID\"" "$ABORT_LOG" 2>/dev/null | tail -1)
  ERROR_LINE=$(echo "$ABORT_ROW" | jq -r ".error // \"unknown\"" 2>/dev/null)
  DURATION_MS=$(echo "$ABORT_ROW" | jq -r ".durationMs // 0" 2>/dev/null)

  # Noise filter
  case "$ERROR_LINE" in
    *"quiet-hours"*|*"couldn'\''t generate"*|*"context window"*|*"rate_limit"*|*"ECONNREFUSED"*)
      echo "incident-digest: noise-filtered ($ERROR_LINE)"
      exit 0
      ;;
  esac
  if [ -n "$DURATION_MS" ] && [ "$DURATION_MS" != "null" ] && [ "$DURATION_MS" -lt 60000 ]; then
    echo "incident-digest: fast-fail filtered (duration ${DURATION_MS}ms < 60000ms)"
    exit 0
  fi

  # Write guard stamp BEFORE doing the synthesis work — ensures rate-limit
  # holds even if synthesis fails mid-way
  date -u +"%Y-%m-%dT%H:%M:%SZ" > "$GUARD_FILE"

  # Derive slug + date for the principle filename
  DATE=$(date +%Y-%m-%d)
  # Short slug from the first 6 words of the error line, kebab-cased
  SLUG=$(echo "$ERROR_LINE" | tr "[:upper:]" "[:lower:]" | tr -c "a-z0-9" "-" | tr -s "-" | cut -c1-60 | sed "s/^-//;s/-$//")
  [ -z "$SLUG" ] && SLUG="unclassified"
  OUT="$KB_DIR/incident-$SLUG-$DATE.md"

  # Synthesis is done by the agent, not this shell. This skill prepares the
  # skeleton + evidence and the agent fills the Principle and Anti-pattern.
  # Agent reads $SESSION_FILE + $ABORT_ROW, then writes the final note over
  # this skeleton using the Edit tool.

  cat > "$OUT" <<EOF
# Incident: $ERROR_LINE

Date: $DATE
Session: $SESSION_ID
Duration: ${DURATION_MS}ms

## When to apply

TODO — agent fills: concrete trigger conditions (what task shape, what
code area, what signals) that should cause future-Ranveer to pause and
re-read this note.

## The principle

TODO — agent fills: one-to-two sentence durable rule. No references to
this specific session. Must be reusable across tasks.

## Evidence

- Abort log row: \`$ABORT_ROW\`
- Session transcript: \`$SESSION_FILE\`
- Error first line: \`$ERROR_LINE\`

## Anti-pattern

TODO — agent fills: what specifically went wrong here, stated as a
reusable anti-pattern (not a session-specific narrative).

## Studio-os / content-engine / openclaw example

TODO — agent fills: concrete example from our real repos where this
principle applies. Pick one that is load-bearing, not a toy case.

## Curriculum domain

TODO — agent fills: which domain in curriculum.yaml this belongs to
(code-review, testing-strategy, error-handling, observability, ci-cd,
security, performance, refactoring, incident-response, or
architecture-patterns). Then increment that domain'\''s priority by 1 if
priority > 1 (priority 1 stays at 1).
EOF

  echo "incident-digest: skeleton written to $OUT"
  echo "incident-digest: agent must now fill TODOs via Edit tool then bump curriculum priority"
  echo "SKELETON_PATH=$OUT"
' _ "$SESSION_ARG"
```

## Agent follow-up (after skeleton is written)

When the skill returns `SKELETON_PATH=<path>`, Ranveer must:

1. **Read** the session transcript (`$SESSION_FILE` from the evidence
   block) and the abort row.
2. **Edit** the skeleton file, replacing each `TODO — agent fills: ...`
   block with real content. Follow the format rules in the skeleton.
3. **Update `curriculum.yaml`** — find the matching domain, bump its
   `priority` by 1 (unless already 1), set `updated:` to today.
4. **Post ONE line to `#code`** (channel `C0AM06M0JE8`):
   `"Logged a lesson from today's incident: <one-sentence principle>."`
   Plain English, no paths, no session ids.

## Why this exists

Sessions end and their lessons die with them. Without post-incident
synthesis, Ranveer will repeat the same mistake next month. The 2025
agent-memory surveys (Mem^p, Formation-Evolution-Retrieval) converge on
the same finding: agents that distill failure trajectories into durable
rules achieve steadily higher success rates on analogous tasks.

The loopguards above exist because this skill is fired BY the watchdog
on `agent_end: success=false` — and the watchdog fires every time the
ranveer agent returns an error, including transient ones. Without rate-
limiting + noise filtering + recursion guards, a broken auto-revive
cron (like the one at `consecutiveErrors: 5` on 2026-04-16) would spam
#code with digests every 5 minutes.

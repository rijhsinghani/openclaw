---
name: ranveer-daily-digest
description: 'End-of-day digest: summarize today''s autonomous merges, any escalated/blocked PRs with reasons, and preview tomorrow''s top-3 proposals from the next morning''s backlog scan. Posts a single formatted Slack message to #code at 17:00 ET (cron: ranveer-daily-digest). Use when assembling Ranveer''s daily digest. Triggers include: ''ranveer daily digest'', ''daily digest'', ''ranveer end of day'', ''eod summary''.'
metadata:
  openclaw:
    emoji: 📋
    requires:
      bins:
      - bash
      - jq
      - node
---

# Ranveer Daily Digest

Post a single end-of-day summary to `#code` so Sameer can review autonomous activity in one glance.

## When this skill runs

- **Cron**: `ranveer-daily-digest` (17:00 ET, Mon-Fri)
- **On demand**: Sameer asks "Ranveer, today's digest"

## Data sources

Read-only. All paths are absolute under `$HOME/.openclaw/`. Always prefix with `$HOME/.openclaw/` or `~/.openclaw/` when reading — bare `agents/...` and bare `~/agents/...` both resolve to the wrong location.

1. `$HOME/.openclaw/agents/ranveer/data/audit/autonomous-runs.jsonl` — autonomous batch state transitions (this agent's audit).
2. `$HOME/.openclaw/agents/ranveer/data/audit/ship-runs.jsonl` — the canonical merge audit (written by `ship.sh`).
3. Today's briefings directory: `$HOME/.openclaw/ranveer-reports-private/briefs/ranveer-backlog-*.html`.

Filter all records to today (America/New_York timezone, 00:00–23:59).

## Digest sections

**1. Merges shipped (autonomous)**

For each row in `ship-runs.jsonl` where `branch` starts with `ranveer/auto/`, `stage=="merge"`, `status=="success"`, today's date: format as `- #<pr_number> <task_slug> (<duration_seconds/60> min)`.

**2. Escalated / blocked**

Every autonomous run in `autonomous-runs.jsonl` today where `status ∈ {escalated, failed}` and no subsequent success row for the same `task_slug`: format as `- <task_slug> — <reason>` (e.g., `cr_requested_changes`, `hard_gate_file:*`, `daily_cap_reached:*`).

**3. Tomorrow's top-3**

Read the most recent backlog brief from this afternoon's scan (15:00 ET). List its top-3 proposals ranked by composite score.

## Cleanup outcomes section (new)

Before composing the message, compute three counts using `jq`. All timestamps are UTC-stamped; filter to today (America/New_York) by comparing the `ts` prefix against the NY date string (`TZ=America/New_York date +%Y-%m-%d`).

```bash
TODAY_NY=$(TZ=America/New_York date +%Y-%m-%d)
AUDIT_BASE="$HOME/.openclaw/agents/ranveer/data/audit"

# Auto-merged trivial/small PRs via ship-runs.jsonl
MERGED=$(jq -r --arg d "$TODAY_NY" \
  'select(.branch != null and (.branch | startswith("ranveer/auto/"))
    and .stage=="merge" and .status=="success"
    and (.ts | startswith($d))) | .branch' \
  "$AUDIT_BASE/ship-runs.jsonl" 2>/dev/null | wc -l | tr -d ' ')

# Medium plans queued for approval via proactive-cleanup.jsonl
QUEUED=$(jq -r --arg d "$TODAY_NY" \
  'select(.event=="plan_queued" and .tier=="medium" and (.ts | startswith($d))) | .tier' \
  "$AUDIT_BASE/proactive-cleanup.jsonl" 2>/dev/null | wc -l | tr -d ' ')

# Large items logged to backlog via debt-backlog.jsonl
BACKLOG=$(jq -r --arg d "$TODAY_NY" \
  'select(.event=="large_logged" and (.ts | startswith($d))) | .event' \
  "$AUDIT_BASE/debt-backlog.jsonl" 2>/dev/null | wc -l | tr -d ' ')
```

If all three counts are 0, **skip the cleanup section entirely** — emit nothing, no heading, no zeros. Do not add empty noise.

If any count is non-zero, append this block to the digest message (after "Tomorrow's proposals"):

```
Today's cleanup:
• <MERGED> tech-debt PRs auto-merged (unused imports, dead code, etc.)
• <QUEUED> medium refactors queued for your approval (awaiting your review)
• <BACKLOG> items logged for weekly review
```

Rules:
- Omit a bullet line entirely if that count is 0 (e.g. if MERGED=0, don't show the auto-merged line).
- If QUEUED > 0 and a plan file path is available from `proactive-cleanup.jsonl` (field `plan_file`), replace "awaiting your review" with the filename (basename only, no path).
- Never show file paths, exit codes, or jq commands in the Slack message — plain English only.

## Message format

```
Daily digest — <YYYY-MM-DD>
Merged: <N>  |  Escalated: <M>  |  Cap used: <M>/3

Merges:
<bullet list>

Escalated:
<bullet list>

Tomorrow's proposals:
1. <repo>: <title>
2. <repo>: <title>
3. <repo>: <title>

Today's cleanup:           ← omit entire block if all counts are 0
• X tech-debt PRs auto-merged (unused imports, dead code, etc.)
• Y medium refactors queued for your approval (awaiting your review)
• Z items logged for weekly review
```

Keep total message ≤ 40 lines. If a section is empty, say `(none)` — except the cleanup section which is omitted entirely when all zeros.

## Hard rules

- **Read-only** — never modify audit files, never create PRs.
- **Single post per day** — check today's audit for an existing `{stage:"digest",status:"posted"}` row; skip if present.
- **Never crash on malformed audit lines** — skip and continue.
- **Respect autonomy flag** — read `jq -r '.enabled' $HOME/.openclaw/agents/ranveer/autonomy.json`. If false, still post a minimal digest (`Autonomous mode off today`) so the cron watchdog sees it fired. NOTE: autonomy lives in this sidecar file, NOT in `openclaw.json`.

## OpenClaw pin-drift check (runs every digest)

Before posting the digest, run:

```
bash /Users/sameerrijhsinghani/.openclaw/agents/ranveer/scripts/check-openclaw-pin.sh
```

The script compares `~/.openclaw/patches/PINNED-VERSION.txt` against the
installed OpenClaw version. On drift it self-posts a warning to `#code` and
still exits 0. Do not treat drift as a digest failure — it is its own alert.
If the script prints `DRIFT:` add a one-line note at the top of the digest:
`⚠️ OpenClaw pin drift detected — see separate alert above.`

## Output contract

Single Slack message posted to `#code` (`C0AM06M0JE8`), plus audit row `{stage:"digest",status:"posted",ts:"..."}` appended to `agents/ranveer/data/audit/autonomous-runs.jsonl`.

---
name: ranveer-post-ship-wiring
description: "When you ship a capability another agent will USE (Anisha calling a new carousel generator, a future agent hitting a new service), you must update the consumer agent's skills + knowledge + usage doc in the SAME PR. Use whenever your plan artifact mentions 'Anisha will use this' or 'consumer agent needs to call this' — a capability with no consumer wiring is a ghost."
metadata:
  openclaw:
    emoji: "🔌"
    requires:
      bins: ["bash"]
---

# ranveer-post-ship-wiring — Consumer Wiring Contract

When you ship a capability that another agent will USE, you MUST in the same turn update the consumer agent's access. Do NOT ship the engineering change without also shipping the consumer wiring — a capability no agent can invoke is a ghost, same failure mode as the phantom-skills incident from 2026-04-16 (9 skills referenced, zero built, Codex burned 6.8M tokens chasing tools that didn't exist).

## Checklist

### 1. Skills list

If the consumer needs a new skill to invoke your capability:

- Add to `skills` array in `~/.openclaw/openclaw.json` under `agents.list[].skills`
- Build the SKILL.md at `~/.openclaw/workspace-<name>/skills/<skill>/SKILL.md`

### 2. Knowledge doc

Write or update `~/.openclaw/agents/<consumer>/knowledge/<capability>-usage.md` with:

- One-line "what this is"
- CLI invocation example they can copy-paste
- Expected output shape
- Error modes and what to do about each

### 3. Handoff cue

If the consumer needs to know WHEN to use the capability, add a one-line hint to their `HEARTBEAT.md` or `SOUL.md`:

> "When Sameer asks for a carousel, run `Skill('carousel-generate', '--brand X')`."

### 4. Validate

```bash
/opt/homebrew/bin/openclaw config validate
```

### 5. Notify

Post ONE Slack message to the consumer's channel:

> "New capability available: [one sentence]. Usage doc at `knowledge/<file>.md`."

## Trigger phrase

If your plan artifact includes "Anisha will use this" or "consumer agent needs to call this" — post-ship consumer wiring is required in the same PR.

## Cross-notify Anisha on gap fixes

**Trigger:** the commit message on a merged PR contains the pattern `GAP-\d{4}-\d{2}-\d{2}-[A-Z]` (e.g. `GAP-2026-04-19-A`).

**Step 0 — check consumer.** Look up `consumer` in the task spec that produced this PR. If `consumer != "anisha"`, stop here — no cross-notify needed.

**Step 1 — DURABLE STATE FIRST.** Before posting to Slack, write the fix record to `~/.openclaw/runtime/gaps.jsonl`:

```bash
# Use flock to prevent concurrent writes; use fsync-safe temp-then-rename pattern
flock ~/.openclaw/runtime/gaps.jsonl.lock bash -c '
  TMPFILE=$(mktemp ~/.openclaw/runtime/gaps.jsonl.XXXXXX)
  # Read existing, update matching row status, write to tmp, then mv into place
  python3 -c "
import sys, json, os, datetime
gap_id = sys.argv[1]
pr_url = sys.argv[2]
path = os.path.expanduser(\"~/.openclaw/runtime/gaps.jsonl\")
rows = []
if os.path.exists(path):
    with open(path) as f:
        rows = [json.loads(l) for l in f if l.strip()]
found = False
for row in rows:
    if row.get(\"gap_id\") == gap_id:
        row[\"status\"] = \"fixed\"
        row[\"pr_url\"] = pr_url
        row[\"fixed_at\"] = datetime.datetime.utcnow().isoformat() + \"Z\"
        found = True
with open(\"$TMPFILE\", \"w\") as f:
    for row in rows:
        f.write(json.dumps(row) + \"\n\")
    f.flush()
    os.fsync(f.fileno())
" "$GAP_ID" "$PR_URL"
  mv "$TMPFILE" ~/.openclaw/runtime/gaps.jsonl
'
```

**Step 2 — THEN post to `#content`.** Only after the gaps.jsonl write succeeds (exit 0):

```bash
openclaw message send \
  --account default \
  --target "channel:C0AGG5L97EG" \
  -m "Anisha — \`${GAP_ID}\` shipped in PR ${PR_URL}. Retest on your next heartbeat."
```

**Ordering matters.** If the Slack post succeeds but the `gaps.jsonl` write fails, Anisha thinks it's fixed but there is no state to retest against. Durable write FIRST, Slack second — always.

**Note:** post as `--account default` (Ranveer bot), not as Anisha's account. This is Ranveer notifying Anisha, not Anisha self-posting.

## Channels reference

- Anisha's channel: `C0AGG5L97EG`
- Ranveer's own channel (`#code`): `C0AM06M0JE8`

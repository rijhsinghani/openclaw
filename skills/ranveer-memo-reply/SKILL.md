---
name: ranveer-memo-reply
description: "Handle Sameer's replies on Production Readiness memo threads and block_action button events in #code. Routes plain-English decisions ('yes do it', 'skip it', 'ship it', 'what's that about') and formal commands ('fix r001', 'defer r002 14d') through the parse-slack-reply pipeline. Use when a message arrives on a memo thread or when a button is tapped."
metadata:
  openclaw:
    emoji: "📨"
    requires:
      bins: ["bash", "python3"]
---

# ranveer-memo-reply — Memo Thread + Button Handler

When Sameer replies in a `#code` thread that contains a Production Readiness memo (look for "Production Readiness:" in the thread), his message is a **decision command**, not a chat question. Run it through the pipeline before answering.

## Text-reply pipeline

```bash
ENG_HYGIENE_THREAD_TS="$THREAD_TS" \
ENG_HYGIENE_MEMO_ID="$(date +%F)" \
ENG_HYGIENE_ACTOR="U03RW6QRM1R" \
python3 ~/.openclaw/agents/ranveer/scripts/parse-slack-reply.py "$MESSAGE_TEXT" \
  | bash ~/.openclaw/agents/ranveer/scripts/handle-decision.sh
```

### The pipeline understands

Plain English:

- "yes do it" / "go ahead" / "ship it" → dispatches fix on top blocker
- "skip it" / "not now" / "later" → defers 7 days
- "what's that about" / "tell me more" → shows urgency math
- "ok" / "got it" → acknowledges

Formal commands:

- `fix r001`, `go r002`, `defer r001 14d`

## Reply format

Post the pipeline's stdout back as a threaded reply.

- `{"status":"dispatched"}` → say "On it."
- `{"status":"pending","reason":"autofix_dispatcher_stub"}` or error about missing files → explain briefly what happened.

**Do NOT try to answer memo-thread replies conversationally.** Always run the pipeline first. The scripts handle all the logic.

## Button click events (block_action)

When Sameer taps a button you receive a system event like:

```json
{
  "interactionType": "block_action",
  "actionId": "openclaw:reply_button:0:1",
  "value": "fix r001"
}
```

Extract `.value` and pipe it through the same pipeline:

```bash
ENG_HYGIENE_THREAD_TS="$MESSAGE_TS" \
ENG_HYGIENE_MEMO_ID="$(date +%F)" \
ENG_HYGIENE_ACTOR="$USER_ID" \
python3 ~/.openclaw/agents/ranveer/scripts/parse-slack-reply.py "$VALUE" \
  | bash ~/.openclaw/agents/ranveer/scripts/handle-decision.sh
```

### Button values you will encounter

- `fix r001` / `fix r002` / ... → fix that blocker
- `defer r001 7d` / `defer r002 7d` / ... → skip for 7 days
- `explain r001` / `explain r002` / ... → show urgency math (routes to `why`)
- `fix all` → dispatch autofix for all eligible blockers
- `report full` → rerun the full daily pipeline
- `quiet today` → suppress today's follow-up alerts

## Backlog proposal buttons

The proactive backlog loop posts `approve backlog / skip backlog / show backlog` buttons. Handle via the same pattern (extract `.value`, pipe through decision pipeline). See `Skill("ranveer-backlog-scan")` for the scan itself.

- **`approve backlog`** — re-run `Skill("ranveer-backlog-scan")` (state may have changed), build task spec for the top item, dispatch via `Skill("ranveer-task-spec")`, report 3 lines, re-enter the backlog loop.
- **`skip backlog`** — note the current top item in memory (don't re-propose this session), re-run scan, propose the next item in same business-language format + buttons. If empty: "Nothing else in the queue right now."
- **`show backlog`** — re-run scan, format top 5 items as numbered list in business language (no file counts / LOC / phase numbers). Thread reply. End with "Which one should I tackle?"

---
name: handoff-complete
description: Enforce the 5-line handoff completion template, find the matching open handoff in ~/.openclaw/data/handoffs/log.jsonl, update it with completion metadata, validate the outbound Slack text, and post the completion visibly in both the originating channel and the closer's own channel.
allowed-tools: Bash, Read, Write
---

# handoff-complete

Shared completion protocol for cross-agent work. Use this when you received a handoff through the CLI path, finished the work, and need the close-out to be visible to Sameer in Slack instead of disappearing back into the spawning terminal.

## When to invoke

- You received a `HANDOFF_SUMMARY:` request from another agent and finished it
- You completed the delegated slice and need to close the loop publicly
- Sameer asked for the full lifecycle to be visible in Slack

## Required 5-line format

Every completion message must contain EXACTLY these 5 numbered lines. Keep the labels verbatim.

```text
1. What I shipped: <one sentence, past tense>
2. Where it landed: <human phrase — "prototypes folder", "PR #123 on sameer-automations", "the skills folder">
3. Handoff this closes: <topic or timestamp of the original request>
4. Anything Sameer needs to do: <yes + what / no>
5. Next step: <"none, closed" | "waiting on X" | concrete next action>
```

No file paths. No exit codes. Plain English only.

## Invocation

Run the dispatcher with the closer's agent id and the completion text passed via a file:

```bash
bash ~/.claude/skills/handoff-complete/dispatch.sh \
  --from <your_agent_id> \
  --message-file <(cat <<'EOF'
1. What I shipped: I finished the handoff-complete skill and wired visible close-out posting.
2. Where it landed: the skills folder
3. Handoff this closes: 2026-04-18T13:47:09Z
4. Anything Sameer needs to do: no
5. Next step: none, closed
EOF
)
```

If multiple open handoffs could match, pass the original handoff timestamp explicitly:

```bash
bash ~/.claude/skills/handoff-complete/dispatch.sh \
  --from <your_agent_id> \
  --handoff-timestamp <ISO-8601 timestamp from log.jsonl> \
  --message-file <path>
```

## What the dispatcher does

1. Validates the 5 numbered lines and rejects placeholders, paths, and vague fields.
2. Finds the matching OPEN handoff in `~/.openclaw/data/handoffs/log.jsonl`.
3. Updates that JSONL row in place with:
   - `completed_at`
   - `completion_summary`
   - `completion_raw`
   - `completed_by`
4. Runs the outbound text through the same rewrite logic used by `outbound-slack-validator`.
5. Posts the visible completion card to:
   - the originating Slack channel from the matched handoff row
   - the closer's own home channel

## Matching rules

- Preferred: `--handoff-timestamp`
- Otherwise: the dispatcher tries to match line 3 (`Handoff this closes`) against the timestamp or topic of an open handoff assigned to `--from`
- If exactly one open handoff is assigned to `--from`, that row is accepted
- If zero or multiple rows match, the dispatcher rejects the completion

## Why this exists

CLI-spawned handoffs were closing silently. The receiver's "done" note went back to the spawning terminal instead of the Slack channel where Sameer was actually watching. This skill makes the completion durable, visible, and linked to the original log row.

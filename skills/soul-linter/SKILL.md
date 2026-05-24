---
name: soul-linter
description: 'Structural lint for OpenClaw agent SOUL.md files. Detects attention-decay failure modes: size bloat, misplaced critical keywords, rule-density drop, and duplication. Call before committing any SOUL.md / HEARTBEAT.md change. Pure bash + python3, sub-second, no LLM call. Use when linting a SOUL.md file for an OpenClaw agent. Triggers include: ''soul lint'', ''soul linter'', ''check the soul.md'', ''lint soul''.'
metadata:
  openclaw:
    emoji: 🧭
    requires:
      bins:
      - bash
      - python3
      - awk
---

# soul-linter

Long system prompts suffer **attention decay** in the middle: rules that
land past byte ~25K of a bootstrap are reliably ignored by the model,
even when nothing is truncated. We only caught this by accident after
Ranveer broke the `gs://` rule and the post-mortem traced the rule to a
position where the model wasn't paying attention.

This skill is the **structural safeguard** that stops any SOUL.md from
drifting back into a shape the model will ignore.

## When to invoke

Run at these trigger points:

- **Before committing** any edit to `workspace-<agent>/SOUL.md` or
  `agents/<agent>/SOUL.md` (the pre-commit hook does this automatically —
  see below).
- **Before committing** any edit to `HEARTBEAT.md` that references the
  SOUL byte layout.
- **On-demand** when you suspect a playbook has drifted: `bash
  ~/.openclaw/scripts/soul-linter.sh ranveer`.
- **Weekly** via the attention-probe cron (Mon 09:07 / 09:33 ET) — the
  probe calls the linter as a pre-check.

## How to call

```bash
# Lint every SOUL file for an agent (workspace-<agent>/SOUL.md = live; agents/<agent>/SOUL.md = reference)
bash ~/.openclaw/scripts/soul-linter.sh ranveer
bash ~/.openclaw/scripts/soul-linter.sh anisha

# Lint one specific file (used by the pre-commit hook)
bash ~/.openclaw/scripts/soul-linter.sh ranveer --path ~/.openclaw/workspace-ranveer/SOUL.md
```

Exit code `0` = pass, `1` = fail, `2` = error (missing agent, file not
found). Failures print a four-line scorecard explaining which gate
tripped.

## Gates enforced

| Gate              | Threshold                        | Why                                                                              |
| ----------------- | -------------------------------- | -------------------------------------------------------------------------------- |
| Size              | ≤ 12 000 bytes                   | Past this we empirically see rules get ignored. 12K is the empirical safe band.  |
| Keyword top-band  | Critical keywords in first 5K    | If a keyword shows up only after byte 5K the model routinely misses it.          |
| Rule density      | ≥ 0.50 rule-lines / content-line | Playbooks that drift toward rationale and examples hide the actual instructions. |
| Duplication       | 0 normalized-line collisions     | Duplicates waste attention budget and create ambiguity.                          |

## Per-agent keyword lists

The critical-keyword list is agent-specific — Anisha's invariants differ
from Ranveer's, and running the wrong list gives vacuous pass/fail.

**Ranveer (top-band required):** `dispatch-coding`, `gs://`, `anisha`,
`plan artifact`, `MANDATORY`, `NEVER`, `consult-knowledge`, `ship.sh`.

**Anisha (top-band required):** `registry.yaml`, `publish-deliverable`,
`fabricate`, `GAP SPEC`, `ranveer`, `[[tts`, `NEVER`, `MANDATORY`.

To add a new agent: edit `keywords_for_agent()` in
`~/.openclaw/scripts/soul-linter.sh`.

## Pre-commit hook

Installed at `~/.openclaw/.git/hooks/pre-commit`. If the staged diff
touches any `SOUL.md` or `HEARTBEAT.md`, the hook runs this linter
against the affected agent and blocks the commit on failure. Override
for genuine emergencies with `git commit --no-verify` — the hook emits a
warning so the bypass is visible.

## Tuning knobs (env vars)

- `SOUL_LINTER_SIZE_LIMIT` — byte cap (default 12000)
- `SOUL_LINTER_TOP_BAND` — top-band size in bytes (default 5000)
- `SOUL_LINTER_DENSITY_MIN` — rule-density floor (default 0.50)

Keep defaults unless you have empirical data showing otherwise. The
current thresholds match the incident that triggered this skill.

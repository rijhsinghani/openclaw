---
name: ranveer-gap-intake
description: 'Intake protocol when you receive a programmatic spawn from Anisha via ''openclaw agent'' CLI (first message starts with ''GAP SPEC''). You scope the capability gap — audit existing code, produce a delta plan, publish as HTML deliverable, post link + 3-line summary in #code, and WAIT for ''ranveer go'' before any build. Never execute on a GAP SPEC intake. Use when intake-ing a new GAP SPEC for Ranveer. Triggers include: ''ranveer gap intake'', ''gap spec'', ''ranveer gap'', ''new task for ranveer''.'
metadata:
  openclaw:
    emoji: 🤝
    requires:
      bins:
      - bash
      - grep
---

# ranveer-gap-intake — Cross-Agent Intake from Anisha

When you receive a session whose first message contains `GAP SPEC` (per `~/.openclaw/workspace/CROSS-AGENT.md`), it's a programmatic spawn from Anisha asking you to scope a capability gap. Treat it as urgent.

## Protocol

### 1. Acknowledge immediately in #code (one line, no analysis yet)

```
On it — scoping <capability> for <client>. Back in ~5 min.
```

### 2. Run the reuse audit FIRST

Per the `existence-check-first` rule:

- Grep across relevant repos (studio-os, content-engine, automation_consulting, .openclaw)
- Check for related services, n8n workflows, edge functions, migrations
- Look for CLAUDE.md inventory docs in subdirs

### 3. Produce a DELTA plan ONLY — do NOT build, commit, or branch

The plan must include:

- **Reuse audit findings**: `BUILT+WIRED / BUILT-BUT-UNWIRED / PARTIAL / MISSING` per capability, with file paths
- **What to build**: services, routes, migrations, n8n nodes, per-repo
- **External dependencies + monthly costs**
- **Scope estimate** (days)
- **Risks / gotchas**

### 4. Publish as HTML deliverable

```bash
publish-deliverable \
  --persona=ranveer \
  --category=briefs \
  --classification=internal-only \
  --file=/tmp/ranveer-gap-plan-<client>-<ts>.html \
  --title="<capability> build plan for <client>" \
  --summary="<3-line summary>"
```

### 5. Post back in #code

- Link to the deliverable (no `gs://` — use the clickable URL the publisher returns)
- 3-line business-English summary
- End with: _"Approve this plan and I'll start the build. Say 'ranveer go' to start."_

### 6. Do NOT execute

Wait for Sameer's explicit `ranveer go` approval before any code changes.

## Why this matters

Anisha can't post a Slack message asking you to do something — Slack messages between agents don't trigger your session. The `openclaw agent` CLI spawn is the only handoff that reaches you. When you see one, it's load-bearing for the client engagement.

## Read the full protocol on first cross-agent intake each session

```bash
cat ~/.openclaw/workspace/CROSS-AGENT.md
```

## Escalating TO Anisha (reverse direction)

If the task is brand / copy / content / UX wording / social research, hand OFF to Anisha instead of doing it yourself:

```bash
openclaw agent --agent anisha --message "GAP SPEC: <restate the task in one paragraph>"
```

Post one short line to #code: "This is Anisha's domain — I handed it off to her, she'll post findings here."

Full field schema + worked examples: `~/.openclaw/agents/ranveer/knowledge/anisha-handoff.md`.

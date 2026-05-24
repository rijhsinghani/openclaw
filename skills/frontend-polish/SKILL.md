---
name: frontend-polish
description: 'Coordinates a brand/polish review for frontend components by delegating to Anisha (brand expert). Ranveer detects the trigger, asks Sameer for approval, packages the request, invokes Anisha, parses her brief, and dispatches approved changes to Codex. Use when polishing frontend visuals after a fix. Triggers include: ''frontend polish'', ''polish the UI'', ''frontend pass'', ''visual cleanup''.'
---

# Skill: frontend-polish

**Owner:** Ranveer (coordinator) + Anisha (reviewer)
**Model:** Anisha runs Gemini 3.1 Pro natively — no separate API call needed from Ranveer
**Cost:** ~$0.05–$0.15 per pass (Anisha's Gemini session). Requires Sameer approval before running.
**Daily cap:** Anisha enforces her own cap of 5 design-polish-review passes/day.

> **Architecture note (2026-04-16):** Ranveer no longer calls Gemini directly.
> Anisha owns the brand/polish voice — single source of truth. Ranveer coordinates.
> Old direct path (`dispatch-litellm.sh --mode frontend-polish`) is deprecated and exits 1.

## What this skill does

1. **Detects** a frontend-polish trigger (file types, keywords, or `--polish` flag)
2. **Asks Sameer** via Slack button before doing anything
3. **On approval**: packages the component + task description into a request file and **invokes Anisha**
4. **Anisha reviews** against her canonical brand standards and writes a structured brief
5. **Ranveer parses** her brief and posts the top 3 recommendations to Sameer with Approve/Deny buttons
6. **On approval**: dispatches to Codex with Anisha's specific guidance

## When to invoke

**Offer it** (post Slack button, don't fire) when the task or PR touches any of:

- File extensions: `.tsx`, `.jsx`, `.css`, `.scss`, `globals.css`, `theme.ts`
- Tailwind config: `tailwind.config.*`
- Directories: `/components/`, `/app/(client)/`, `/design-system/`, `/ui/`
- Task keywords: "UI", "frontend", "design", "polish", "client-facing", "portal", "page",
  "component", "responsive", "mobile", "premium", "quiet luxury", "aesthetic"
- Sameer writes `--polish` anywhere in his task message

**Never auto-invoke.** Always offer via Slack button and wait for explicit approval.

## Step-by-step invocation

### Step 1 — Offer Sameer the review (Slack button)

Post to #code before doing any work:

```
About to ship frontend changes to <component name>. Want Anisha's design review before it ships?

[[slack_buttons: Yes, get Anisha's review:yes:primary, Ship as-is:no:danger]]
```

Wait for the button click. If `no` → log to audit and stop. If `yes` → continue.

### Step 2 — Build the request file

Read the component file(s) and write a polish request to a timestamped temp file:

```bash
FP_TS=$(date +%s)
FP_REQUEST="/tmp/polish-request-${FP_TS}.md"

cat > "$FP_REQUEST" <<BRIEF
# Polish Review Request from Ranveer

**Timestamp:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Task description:** <what is being built — plain English>
**Target brand standard:** Premium photography studio, quiet luxury — minimal, warm, unhurried.

## Component file(s)

### <ComponentName>.tsx

\`\`\`tsx
<file contents — paste up to 300 lines; truncate with "... [truncated N lines]" if longer>
\`\`\`

## Specific questions for Anisha

- Is the CTA prominent enough without being aggressive?
- Does the spacing feel premium or cramped?
- Is any copy too transactional/loud for the brand voice?
- Are interaction states (hover, focus, loading) present on all interactive elements?

## Response file

Please write your structured JSON response to: /tmp/polish-response-${FP_TS}.md
BRIEF
```

### Step 3 — Invoke Anisha

```bash
openclaw agent --agent anisha \
  --message "POLISH REVIEW REQUEST — see ${FP_REQUEST}. Invoke your design-polish-review skill against that file. Write your response to /tmp/polish-response-${FP_TS}.md and post a plain-English summary to #code tagging Ranveer." \
  --timeout 600
```

Anisha is the native Gemini 3.1 Pro agent — no LiteLLM call needed. She reads the request file, runs her review inline, writes the response, and posts a summary to #code.

### Step 4 — Parse Anisha's response

Wait for the response file (poll up to 5 minutes):

```bash
WAITED=0
while [[ ! -f "/tmp/polish-response-${FP_TS}.md" && $WAITED -lt 300 ]]; do
  sleep 10
  WAITED=$((WAITED + 10))
done
```

Parse the JSON block from her response file:

```bash
REVIEW=$(python3 -c "
import sys, json, re
txt = open('/tmp/polish-response-${FP_TS}.md').read()
m = re.search(r'\`\`\`json\n(.*?)\`\`\`', txt, re.DOTALL)
if m:
    print(m.group(1))
else:
    # Try raw JSON
    start = txt.index('{')
    print(txt[start:])
" 2>/dev/null)

SCORE=$(echo "$REVIEW" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read()).get("polish_score",0))' 2>/dev/null || echo 0)
TOP3=$(echo "$REVIEW" | python3 -c 'import sys,json; [print(f"{i+1}. {r}") for i,r in enumerate(json.loads(sys.stdin.read()).get("top_3_gaps",[])[:3])]' 2>/dev/null || echo "No recommendations")
```

### Step 5 — Present to Sameer

```
Anisha's design review for <component>: <score>/10

Top 3 recommendations:
<TOP3>

[[slack_buttons: Apply all:all:primary, Pick individually:pick, Ship as-is:skip:danger]]
```

### Step 6 — Dispatch to Codex (on approval)

On `all`: build a single Codex task spec with all 3 recommendations and dispatch via `dispatch-codex.sh`.

On `pick`: post each recommendation as a separate button for individual approval, then batch the approved ones.

On `skip`: log to audit (`data/audit/frontend-polish.jsonl`), no dispatch.

Codex task spec description template:

```
Anisha's design review for <component> scored <score>/10. Apply the following brand upgrades:
1. <rec 1>
2. <rec 2>
3. <rec 3>

Brand standard: quiet luxury, warm neutrals (stone/slate), subtle transitions (duration-200),
generous whitespace, mobile-first (375px). Full review at /tmp/polish-response-<ts>.md.
```

## Audit log

Every pass (success or refused) appended to:
`~/.openclaw/agents/ranveer/data/audit/frontend-polish.jsonl`

Fields: `ts`, `component_file`, `task_desc`, `reviewer`, `status`, `polish_score`, `anisha_request_file`, `anisha_response_file`

## Error handling

- If Anisha doesn't respond within 5 minutes: post "Anisha's review timed out — ship as-is or retry?" to #code with buttons.
- If response file is malformed JSON: post raw summary from #code thread and ask Sameer to pick manually.
- If `openclaw agent --agent anisha` fails: fall back to `openclaw message send --account anisha --target C0AGG5L97EG` with the same message (async, she picks it up on next wake).

## Cross-agent reference

- Full invocation pattern: `agents/ranveer/knowledge/anisha-handoff.md` → Scenario 4
- Anisha's side: `agents/anisha/knowledge/ranveer-polish-request.md`
- Anisha's skill: `workspace-anisha/skills/design-polish-review/SKILL.md`

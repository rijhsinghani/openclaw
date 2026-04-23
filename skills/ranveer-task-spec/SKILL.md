---
name: ranveer-task-spec
description: "Full task spec JSON schema and dispatch flow for Codex code changes. Use EVERY time you need to edit source code: write the spec to data/state/task-specs/, run dispatch-codex.sh (or dispatch-codex-detached.sh for long tasks), parse exit codes, report to Slack. Covers tier-3 forbidden paths, acceptance criteria, max_duration_seconds, dry_run flag, and exit code semantics."
metadata:
  openclaw:
    emoji: "🔧"
    requires:
      bins: ["bash", "jq"]
---

# ranveer-task-spec — Codex Dispatch Contract

Every source-code change Ranveer makes routes through dispatch-codex.sh or dispatch-codex-detached.sh for long tasks. This skill is the full contract.

## Idle Timeout Protection (NEW)

OpenClaw has a 120-second idle timeout. When Codex runs for longer without producing output, the session gets killed.

Rule: Use dispatch-codex-detached.sh when max_duration_seconds is greater than 90.

| Task Duration | Dispatcher to Use |
|---------------|-------------------|
| 90 seconds or less | dispatch-codex.sh (foreground) |
| More than 90 seconds | dispatch-codex-detached.sh (background) |

### Detached mode workflow

1. **exec** — run ~/.openclaw/agents/ranveer/scripts/dispatch-codex-detached.sh spec.json
2. **parse** — stdout returns job_id, pid, status_file, log_file
3. **poll** — check status_file until status is completed or failed
4. **report** — post result to Slack

Example poll loop:
```bash
while true; do
  STATUS=$(cat ~/.openclaw/agents/ranveer/data/codex-status/${JOB_ID}.json | jq -r .status)
  [[ "$STATUS" == "completed" || "$STATUS" == "failed" ]] && break
  sleep 10
done
```

## Required tool sequence

1. **write** — create ~/.openclaw/agents/ranveer/data/state/task-specs/ranveer-task-TIMESTAMP.json
2. **exec** — run appropriate dispatcher based on duration
3. **report** — post the result to Slack per exit-code table

## Task spec JSON schema

```json
{
  "task_id": "r001-fix-stub-booking-router",
  "type": "apply-patch",
  "target_repo": "/Users/sameerrijhsinghani/studio-os",
  "target_files": ["apps/client-portal/lib/services/booking.ts"],
  "description": "Replace the STUB return at line 42...",
  "acceptance_criteria": ["No STUB remains", "pnpm type-check passes"],
  "tier": 2,
  "max_duration_seconds": 600,
  "dry_run": false
}
```

### Key field rules

- task_id: short slug, kebab-case
- type: apply-patch, refactor, add-tests, or transform
- target_files: NEVER include auth, payment, stripe, clerk, webhook, billing, secret, migration, schema, router, handler
- tier: always 2 (never 3)
- max_duration_seconds: 600 for fixes, 1200 for refactors. If greater than 90, use detached mode.

## Exit codes (foreground mode)

| Exit | Meaning | Action |
|------|---------|--------|
| 0 | Success | Parse JSON, ship if success status |
| 1 | Malformed spec | Fix and retry |
| 2 | Tier-3 block | Needs manual approval |
| 3 | Codex error | Report stderr |
| 4 | Timeout | Use detached mode next time |

## Exit codes (detached mode)

| Exit | Meaning | Action |
|------|---------|--------|
| 0 | Child spawned | Poll status_file |
| 1 | Invalid spec | Fix and retry |

## What you MUST NOT do

- Claim "Codex is working" without actually running the dispatcher
- Edit source files directly — ALL coding routes through dispatchers
- Skip acceptance_criteria

## When dispatch is NOT required

Questions requiring no edits — "how many TODOs?", "is n8n cron healthy?" — answer directly.

## Reference

- Foreground dispatcher: ~/.openclaw/agents/ranveer/scripts/dispatch-codex.sh
- Background dispatcher: ~/.openclaw/agents/ranveer/scripts/dispatch-codex-detached.sh
- Status directory: ~/.openclaw/agents/ranveer/data/codex-status/
- Idle timeout fix docs: ~/.openclaw/workspace-ranveer/knowledge/codex-idle-timeout-fix.md
- Plan artifact: agents/ranveer/knowledge/plan-artifact-format.md

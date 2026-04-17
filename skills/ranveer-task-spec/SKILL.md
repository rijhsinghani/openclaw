---
name: ranveer-task-spec
description: "Full task spec JSON schema and dispatch flow for Codex code changes. Use EVERY time you need to edit source code: write the spec to data/state/task-specs/, run dispatch-codex.sh, parse exit codes, report to Slack. Covers tier-3 forbidden paths, acceptance criteria, max_duration_seconds, dry_run flag, and exit code semantics (0/1/2/3/4)."
metadata:
  openclaw:
    emoji: "🔧"
    requires:
      bins: ["bash", "jq"]
---

# ranveer-task-spec — Codex Dispatch Contract

Every source-code change Ranveer makes routes through `dispatch-codex.sh`. This skill is the full contract.

## Required tool sequence (non-negotiable)

1. **write** — create `~/.openclaw/agents/ranveer/data/state/task-specs/ranveer-task-<timestamp>.json` with the task spec. Use a real write tool call, not narration. `mkdir -p` the directory first if needed. Write to a `.tmp` file and `mv` into place so the spec is never partially written.
2. **exec** — run `bash ~/.openclaw/agents/ranveer/scripts/dispatch-codex.sh <path>`. Real exec call — capture stdout + exit code.
3. **report** — post the result to Slack per the exit-code table below.

If you describe what the tools *would* return instead of calling them, that is a production failure (ref: debug session 2026-04-12, iter 1). Hallucinated tool output has shipped broken state in the past.

## Task spec JSON schema

```json
{
  "task_id": "r001-fix-stub-booking-router",
  "type": "apply-patch",
  "target_repo": "/Users/sameerrijhsinghani/studio-os",
  "target_files": ["apps/client-portal/lib/services/booking.ts"],
  "description": "Replace the STUB return at line 42 with the real Supabase call. Use the existing supabase client at lib/supabase.ts. Match the error-handling pattern in lib/services/gallery.ts.",
  "acceptance_criteria": [
    "No STUB string remains in booking.ts",
    "Function returns real Supabase data with typed result",
    "pnpm type-check passes"
  ],
  "tier": 2,
  "max_duration_seconds": 600,
  "dry_run": false
}
```

### Field rules

- `task_id` — short slug, kebab-case, references blocker id when relevant.
- `type` — one of `apply-patch`, `refactor`, `add-tests`, `transform`.
- `target_repo` — absolute path to one of:
  - `/Users/sameerrijhsinghani/studio-os`
  - `/Users/sameerrijhsinghani/content-engine`
  - `/Users/sameerrijhsinghani/dev/investment-accounting`
  - `/Users/sameerrijhsinghani/.openclaw`
- `target_files` — repo-relative paths. NEVER include `auth`, `payment`, `stripe`, `clerk`, `webhook`, `billing`, `secret`, `migration`, `schema`, `router`, `handler` in the path — those are tier-3 blocked and the dispatcher will exit 2.
- `description` — concrete instructions for Codex. Reference existing patterns. Do not be vague.
- `acceptance_criteria` — testable assertions. Include at least one CI command (`pnpm type-check`, `pnpm test`, `pnpm lint`).
- `tier` — `2` for normal work, never `3`.
- `max_duration_seconds` — `600` for most fixes, `1200` for larger refactors.
- `dry_run` — `false` for real work, `true` only for smoke testing.

## Exit codes

| Exit | Meaning                                                     | Action                                                          |
| ---- | ----------------------------------------------------------- | --------------------------------------------------------------- |
| 0    | Success — parse stdout JSON, look at `.status`              | `success` → ship; `partial` → report what's left                |
| 1    | Task spec malformed                                         | Fix the spec and retry                                          |
| 2    | Tier-3 block — target_files hit a forbidden pattern         | Do NOT retry. Needs Sameer's manual approval                    |
| 3    | Codex itself errored                                        | Report stderr to Sameer. Do NOT retry without his input         |
| 4    | Timeout                                                     | Bump `max_duration_seconds` and retry ONCE, or report to Sameer |

## Slack response by outcome

Top-level message (business English, your normal voice rules apply):

- **Success** → "Done. [one-line summary of what changed]. Branch pushed, ready for `/ship`."
- **Partial** → "Mostly done. [what worked]. [what's left]. Want me to retry the rest?"
- **Tier-3 block** → "Blocked. That touches [path] which is tier-3 (auth/payment/etc). Needs your manual pass."
- **Codex error** → "Codex hit an error. [one-line reason from stderr]. Want me to retry with a tighter scope?"

Technical details (raw JSON, audit row, stderr) go in a thread reply. Never in the top-level.

## Gap-fix PRs must add a regression probe

**Precondition:** If the task spec's `task_id` or `description` references a `GAP-\d{4}-\d{2}-\d{2}-[A-Z]` pattern, the spec MUST include a `regression_probe` field before dispatching to Codex.

```json
{
  "regression_probe": {
    "file": "backend/tests/anisha_self_test/test_mcp_tools.py",
    "test_name": "test_find_prospect_email"
  }
}
```

- `file` — repo-relative path under `content-engine/backend/tests/anisha_self_test/` (or `capabilities.yaml` for manifest updates). The PR diff MUST include an addition or modification to this file.
- `test_name` — pytest node ID that exercises the fixed capability.

**Enforcement — before dispatching to Codex:**

```bash
# Check if task references a GAP-* pattern
if echo "$TASK_SPEC" | grep -qE 'GAP-[0-9]{4}-[0-9]{2}-[0-9]{2}-[A-Z]'; then
  # Verify regression_probe field is present
  PROBE=$(echo "$TASK_SPEC" | jq -r '.regression_probe // empty')
  if [ -z "$PROBE" ]; then
    echo "ERROR: GAP-* fix requires regression probe. Add \`regression_probe\` to task spec." >&2
    exit 5
  fi
fi
```

Exit code `5` = missing regression probe. Do NOT dispatch to Codex. Report to Sameer:

> "Blocked. This fix references `GAP-*` but has no regression probe. Add `regression_probe: {file, test_name}` to the task spec so the fix is verified on Anisha's next heartbeat."

**Rationale:** Without a regression probe, fixes ship without tests. The same bug can return and re-trigger the same gap after probe rotation — the learning loop closes only if every fix adds a test that guards the closure.

## What you MUST NOT do

- Claim "Codex is working on it" without having actually run `dispatch-codex.sh` in this turn.
- Write the task spec inline in a Slack message — write it to disk and run the dispatcher.
- Retry a tier-3 block by renaming the path — the guard is there for safety.
- Edit ANY source file with your own tools (Edit, Write, applyPatch). ALL coding work — single-line fixes included — routes through `dispatch-codex.sh`. This covers studio-os, content-engine, investment-accounting, AND `.openclaw` itself. No size threshold, no "trivial task" exception.
- Skip `acceptance_criteria` — without it Codex has no test for "done".

## When dispatch is NOT required

Questions that require no edit — "how many TODOs in studio-os?", "is the n8n cron healthy?", "what does this function do?" — answer directly, do NOT dispatch.

## Reference

- Dispatcher: `~/.openclaw/agents/ranveer/scripts/dispatch-codex.sh`
- Plan artifact requirement for 3+ file changes: `agents/ranveer/knowledge/plan-artifact-format.md`
- Model-per-worktype routing: `agents/ranveer/knowledge/dispatch-routing.md`

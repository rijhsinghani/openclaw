---
name: ranveer-dispatch
description: "Dispatch a mechanical engineering task to Codex GPT-5.4 via dispatch-batch.sh. Use when Ranveer needs to execute a well-defined, scope-bounded code change (refactor, add tests, apply a patch) without holding the task in his own context. The dispatcher runs each task in an isolated git worktree with schema-validated task specs. Ranveer AUTHORS the spec; Codex EXECUTES. This is how Ranveer keeps his own context lean on long-running hygiene work."
metadata:
  openclaw:
    emoji: "📤"
    requires:
      bins: ["bash", "jq", "python3", "git"]
---

# ranveer-dispatch — Send a Task to Codex via dispatch-batch.sh

Ranveer uses this to offload mechanical code changes to Codex GPT-5.4 running in an isolated worktree. Authoring the spec is cheap; executing the change is what would blow up his context window. Always dispatch rather than edit inline when:

- The task touches more than 3 files
- The task is a mechanical refactor (rename, extract, reformat)
- The task adds tests to an existing module
- The task is tier-1 (reversible) or tier-2 (needs review) but NOT tier-3 (auth/payment/webhook/migration — those require Sameer)

## Script

```
~/.openclaw/agents/ranveer/scripts/dispatch-batch.sh [--parallel N] <dir | spec1.json [spec2.json ...]>
```

## Task spec contract

Every spec MUST validate against:
```
~/.openclaw/agents/ranveer/scripts/schemas/codex-task.schema.json
```

Minimum required fields:

```json
{
  "type": "refactor",
  "target_repo": "/Users/sameerrijhsinghani/studio-os",
  "target_files": ["apps/api/src/lib/errors.ts"],
  "description": "Extract ValidationError, AuthenticationError, ExternalServiceError into a shared @studio/errors package. Update all imports across apps/api and apps/portal. Preserve the retryable flag semantics.",
  "acceptance_criteria": [
    "All three error classes live in packages/errors/src/index.ts",
    "No ValidationError definition remains in apps/",
    "pnpm type-check and pnpm test pass in both apps/api and apps/portal",
    "No runtime behavior change (same throw/catch shapes)"
  ],
  "tier": 2,
  "max_duration_seconds": 1800,
  "dry_run": false
}
```

Optional fields: `task_id`, `branch_prefix`, `allowed_commands`, `commit_message_template`.

## Tier rules

| Tier | Scope                                       | Dispatch allowed?                             |
| ---- | ------------------------------------------- | --------------------------------------------- |
| 1    | Reversible, test-only, doc-only             | YES, autonomously                             |
| 2    | Runtime code but narrow (single module)     | YES, but CodeRabbit must approve before merge |
| 3    | Auth, payment, webhook, DB migration, RBAC  | NO — escalate to Sameer, do NOT dispatch      |

If a spec has `tier: 3`, dispatch-batch.sh refuses with exit 2 BEFORE any codex run. That's the scope guard in `src/ranveer-scope-guard.ts`.

## Workflow

### Step 1 — Author the spec

Write the JSON to `~/.openclaw/agents/ranveer/data/dispatch-queue/<task-slug>.json`. Hand-author; never have Codex itself generate the spec (that's the tier-3 escalation vector this whole system exists to prevent).

```bash
mkdir -p ~/.openclaw/agents/ranveer/data/dispatch-queue
cat > ~/.openclaw/agents/ranveer/data/dispatch-queue/<slug>.json <<'EOF'
{ ...spec... }
EOF
```

### Step 2 — Validate locally

```bash
python3 -c "
import json, jsonschema
spec = json.load(open('$SPEC_PATH'))
schema = json.load(open('$HOME/.openclaw/agents/ranveer/scripts/schemas/codex-task.schema.json'))
jsonschema.validate(spec, schema)
print('ok')
"
```

Only dispatch specs that validate. dispatch-batch.sh will re-validate, but catching failures locally is cheaper.

### Step 3 — Dispatch

Single spec:
```bash
~/.openclaw/agents/ranveer/scripts/dispatch-batch.sh ~/.openclaw/agents/ranveer/data/dispatch-queue/<slug>.json
```

Batch (multiple non-overlapping specs in parallel):
```bash
~/.openclaw/agents/ranveer/scripts/dispatch-batch.sh --parallel 3 ~/.openclaw/agents/ranveer/data/dispatch-queue/
```

Safety: dispatch-batch.sh refuses the batch if ANY two specs share a `target_files` entry. No partial runs.

### Step 4 — Watch the audit log

```bash
tail -f ~/.openclaw/agents/ranveer/data/audit/batch-*.json
```

Each codex dispatch writes a row per stage (start, patch, test, commit, push, pr_open, cr_wait, merge, or fail_<reason>). Use this to answer "is it stuck?" — if no rows for >5 min the state-watchdog cron will post a stale alert to #code.

### Step 5 — Handle results

dispatch-batch.sh exit codes:

| Exit | Meaning                                             | Next move                                                  |
| ---- | --------------------------------------------------- | ---------------------------------------------------------- |
| `0`  | All tasks succeeded and were shipped.               | Post Slack summary: `Shipped N PRs via Codex. See #code.`  |
| `1`  | Pre-flight validation / overlap failure.            | Fix the spec; re-dispatch. Nothing ran.                    |
| `2`  | Tier-3 block on at least one task.                  | STOP. Post blocker line to #code. Wait for Sameer.         |
| `3`  | One or more dispatches failed mid-run.              | Inspect batch-*.json; retry failed specs only.             |

### Step 6 — Slack milestone

After dispatch completes, post ONE line to #code (≤15 words):

- All shipped: `Shipped N fixes via Codex. PRs merged. See ship-runs.jsonl.`
- Partial: `Shipped N of M. Failed: <slug list>. Reviewing logs.`
- Tier-3 block: `Tier-3 task blocked: <slug>. Needs Sameer's approval.`

## Rules

- NEVER edit `dispatch-batch.sh`, `dispatch-codex.sh`, or `src/ranveer-scope-guard.ts` as part of a dispatched task. Those are the dispatcher itself — changes go through Sameer directly.
- NEVER dispatch a spec you haven't hand-validated.
- NEVER batch specs that share a `target_file`. dispatch-batch.sh enforces this but check before queuing to save time.
- NEVER bypass the tier check by lying about a task's tier. Scope guard inspects file paths and will catch you.
- If a dispatch has been running >`max_duration_seconds` + 300, assume it's stuck — kill via the PID in `batch-*.json` and post a stall note.

## Cross-references

- Spec schema: `~/.openclaw/agents/ranveer/scripts/schemas/codex-task.schema.json`
- Scope guard: `~/.openclaw/src/ranveer-scope-guard.ts`
- Audit log format: `~/.openclaw/agents/ranveer/data/audit/batch-*.json`
- Worktree cleanup: dispatch-batch.sh handles `git worktree remove` on exit

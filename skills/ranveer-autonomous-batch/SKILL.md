---
name: ranveer-autonomous-batch
description: "The Autonomous Authority Contract — what you're allowed to do end-to-end after 'ranveer go', the hard-gate file patterns that ALWAYS require explicit approval (auth/stripe/secrets/migrations/deploys), session-level caps (3 merges/day, 2 CR rounds/PR), escape hatches, dry-run mode, and kill switch. Load this skill the moment you read 'ranveer go' or plan any autonomous lifecycle."
metadata:
  openclaw:
    emoji: "🛡️"
    requires:
      bins: ["bash"]
---

# ranveer-autonomous-batch — Autonomous Authority Contract

Sameer granted you a whitelisted scope of end-to-end autonomy. One approval (`ranveer go`) on a briefing thread unlocks the full lifecycle — plan → build → ship → address CodeRabbit → merge — with no further per-step approvals for that batch.

This contract **overrides** the default one-approval-per-task contract for work that falls inside the whitelist. For everything else, the default contract still applies.

## Whitelist (autonomous after `ranveer go`)

- Test coverage additions (unit + integration on critical paths)
- Dead code / unused import removal (via `Skill("dead-code-auditor")`)
- Dependency bumps — patch and minor only, with test verification
- Stale branch cleanup — merged branches + abandoned branches > 14 days
- Merging CR-approved green PRs from trusted agents (`ranveer`, `anisha`, `github-actions[bot]`) or Sameer
- General hardening: lint fixes, typecheck fixes, error-handling gaps, structured-logging additions, timeout/retry on external calls

## Hard gates (ALWAYS require explicit approval — never autonomous)

- **Security-adjacent**: any file under `auth/`, `clerk/`, `stripe/`, `secrets/`, `.env*`, or paths containing `API_KEY`, `SECRET`, `TOKEN`, `PASSWORD`
- **Migrations / schema**: anything in `migrations/` or `supabase/migrations/`, plus `.sql` files
- **Production deploys**: Dockerfiles, CI workflow files under `.github/workflows/`, `cloudbuild.yaml`, `service.yaml`
- **Large blast radius**: PRs > 10 files changed OR additions+deletions > 500 lines
- **Cross-repo refactors**: changes touching > 1 repo in a single PR

The exact regex lives in `$HOME/.openclaw/src/ranveer-scope-guard.ts` (`isHardGateFile`). Pre-flight runs automatically from `$HOME/.openclaw/agents/ranveer/scripts/autonomous-batch.sh`.

## Session-level caps

- **Max 3 autonomous merges / day** across all repos (resets 00:00 ET). Counted from `$HOME/.openclaw/agents/ranveer/data/audit/ship-runs.jsonl` where `branch` starts with `ranveer/auto/` and `stage="merge"` and `status="success"`.
- **Max 4 CodeRabbit escalation rounds per PR** — managed by the `cr-escalation-loop` skill (Codex×2 → Sonnet → Opus → abandon). Never force-merge past CR. Never ping Sameer for stuck PRs — the ladder handles it silently.
- **Monthly spend cap** via the existing `governance.ts` per-persona budget.

## Trigger phrase

`ranveer go` (case-insensitive, must be the entire reply text, optional trailing punctuation) in a thread whose parent is a Ranveer briefing. Any other wording does NOT unlock autonomous mode.

Plain-text reply only. Buttons are NOT wired in the live gateway — the `isRanveerGoTrigger()` / `src/session-router.ts` path is legacy dead code with no runtime effect.

## Escape hatches (MANDATORY — pause the batch immediately)

1. **Hard-gate file surfaced mid-task** — abort the batch, post a scope-change notice, revert to awaiting approval.
2. **CR escalation exhausted (round 5+)** — the `cr-escalation-loop` skill closes the PR silently with an audit log entry. Do NOT ping Sameer. The ladder (Codex×2 → Sonnet → Opus → abandon) manages all rounds autonomously.
3. **Secret/auth/payment code surfaced** — abort the batch entirely. Do not commit; post escalation.
4. **PR balloons beyond caps during execution** (> 10 files or > 500 lines) — split the PR or escalate.

## Dry-run mode

When `agents.list[ranveer].autonomy.dryrun = true` in `openclaw.json` (default for initial deploy), `autonomous-batch.sh` skips real `ship.sh` and posts `would have shipped: <branch>`. Every briefing must include `(dry-run)` in the header so Sameer knows `ranveer go` won't actually merge.

## Kill switch

Set `agents.list[ranveer].autonomy.enabled = false` in `openclaw.json` — or set env `RANVEER_AUTO_DISABLED=1` — to make cron jobs no-op and have `ranveer go` reply "autonomous mode disabled."

## Briefing message format (what unlocks the autonomous flow)

```
<link to ranveer-reports-private brief>
<1-line problem statement>.
<1-line recommendation>.
approve with 'ranveer go' and I'll start the build.
```

Four lines, plain text, no markdown headers. Backlog items #2 and #3 live in a thread reply only on request.

## Approval contract (single-task path)

One approval per task. After Sameer approves, you own the full lifecycle: build task spec JSON, dispatch via `dispatch-codex.sh`, verify output, run CI, report back. Do NOT ask mid-task unless:

1. Scope changes materially (task spec said 2 files, reality is 20)
2. A hard limit trips (tier-3 block, auth/payment code touched)
3. Codex fails after 2 attempts — escalate, don't loop forever

On dispatch success, report 3 lines and re-enter the backlog loop:

```
Done. <one-line summary>. Branch pushed, ready for /ship.
Next: <next item from backlog> — approve?
```

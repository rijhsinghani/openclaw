---
name: ranveer-backlog-scan
description: "Scan all managed repos (studio-os, investment-accounting, content-engine, .openclaw) for hardening work — dead code, ready-to-merge PRs, stale branches > 14 days, coverage gaps — and post a single briefing message to #code with the top proposal. Triggered by cron (ranveer-backlog-scan-am / -pm) or on-demand when Ranveer asks to run it."
metadata:
  openclaw:
    emoji: "🔍"
    requires:
      bins: ["bash", "gh", "git", "jq", "node"]
---

# Ranveer Backlog Scan

Discover the next-highest-value autonomous hardening task and post a briefing to #code.

## When this skill runs

- **Cron**: `ranveer-backlog-scan-am` (09:00 ET, Mon-Fri) and `ranveer-backlog-scan-pm` (15:00 ET, Mon-Fri)
- **On demand**: Sameer asks "Ranveer, run backlog scan"

## On-demand vs scheduled — two very different modes

**Scheduled (cron-triggered: `ranveer-backlog-scan-am` / `-pm`)** — use the full protocol below: run the scan sequence, rank findings, emit the JSONL artifact to `~/.openclaw/agents/ranveer/data/audit/backlog-scan-<YYYY-MM-DD>.jsonl`, fire off proactive-cleanup.sh non-blocking, write the HTML brief, post the briefing to #code. This is the path that populates the artifact other tooling reads.

**On-demand (user says "scan now" / "scan for tech debt" / "find dead code" / "audit this repo" / similar)** — BYPASS any cached-artifact logic. Do NOT read a prior `backlog-scan-*.jsonl` and report from it. Do NOT consult knowledge files first. Go straight to the target repo filesystem, invoke `Skill("dead-code-auditor")` fresh against that repo (or a narrower tool if the request is narrower — grep for TODOs, ast-grep for a pattern, etc.), and report findings inline in the same turn. A previously-written JSONL may be referenced as supplementary context to compare deltas ("this morning's scan flagged X, live code now shows Y"), but it is never the primary source. If the user's request is scoped to a specific repo or path, scope the fresh scan to match — don't widen it to all four repos just because the cron version does.

The user's words: "when i ask him to scan for tech debt i want him to look at the underlying repository, duh." Artifacts are a cache, not a replacement for looking at the code.

## Preconditions (hard-gate — skip posting if any fail)

1. `enabled` must be `true` in the sidecar config `$HOME/.openclaw/agents/ranveer/autonomy.json`. Read via `jq -r '.enabled' $HOME/.openclaw/agents/ranveer/autonomy.json`. If false (or file missing), log "autonomy disabled" and exit 0 without posting. NOTE: the autonomy config lives in this sidecar file, NOT in `openclaw.json` (the openclaw schema rejects the `autonomy` key on agents.list[N]).
2. An earlier briefing for today with no `ranveer go` reply still pending → skip (avoid double-posting).

## Scan sequence

Execute in this order. Stop at the first tier that yields a proposal.

1. **Dead code** — `Skill("dead-code-auditor")` across studio-os, investment-accounting, content-engine. Filter out hard-gate files (auth/, stripe/, secrets/, migrations/, .env, Dockerfile, CI workflow). Rank by (a) unused-export count per file, (b) age since last modification.
2. **Ready-to-merge PRs** — `gh pr list --state open --json number,title,author,isDraft,reviewDecision --repo <repo>` for each repo. Filter to PRs where `isDraft=false`, `reviewDecision="APPROVED"`, last commit > 2h ago (buffer for CI). Author must be a trusted agent (`ranveer`, `anisha`, `github-actions[bot]`) or Sameer.
3. **Stale branches** — `git branch -r --merged main` older than 14 days. Exclude `main`, `HEAD`, and any branch referenced by an open PR.
4. **Coverage gaps** — `pnpm test --coverage` per repo. Surface files < 60% line coverage in critical paths (payment/, booking/, pipeline/).

## Ranking heuristic

Order all findings by composite score:

- **Blast radius** (lower = better): file count, cross-module imports
- **Deploy risk** (lower = better): touches only test/lint/docs → risk 1; touches business logic → risk 3; touches infra/auth/payment → hard-gate (drop)
- **Hardening value** (higher = better): CVE severity, coverage delta, lint violations removed

Top 3 findings survive; top 1 becomes the proposal.

## JSONL output (new — runs before posting)

After ranking but before writing the HTML brief, emit a JSONL file at
`~/.openclaw/agents/ranveer/data/audit/backlog-scan-<YYYY-MM-DD>.jsonl`
(where `<YYYY-MM-DD>` is `$(date +%Y-%m-%d)` in America/New_York).

Write **one JSON object per finding** (all findings, not just top-3), one per line, using this exact schema — no extra keys, no missing keys:

```json
{"tier":"trivial","repo":"/abs/path/to/repo","path":"repo-relative/file.ext","category":"unused-import","description":"One-sentence summary of the issue","match":"optional symbol or pattern, empty string if N/A"}
```

Field rules:
- `tier`: one of `trivial` | `small` | `medium` | `large`
  - **trivial**: single-file, purely mechanical (unused import, dead export, cosmetic lint) — zero API risk
  - **small**: 1–3 files, low blast radius, internal rename or simple refactor
  - **medium**: 3+ files or any change to public API / interface signature
  - **large**: touches auth, payment, migration, schema, or infra — never auto-dispatch
- `repo`: absolute path to the repository root (e.g. `/Users/sameerrijhsinghani/studio-os`)
- `path`: repo-relative path to the primary file (e.g. `apps/client-portal/lib/utils.ts`)
- `category`: one of `unused-import` | `dead-export` | `lint-warning` | `deprecated-code` | `dep-version-bump` | `duplicate-util` | `undocumented-api` | `inefficiency` | `multi-file-refactor` | `api-signature` | `test-restructure` | `architectural` | `db-migration` | `auth-security`
- `description`: plain-English one-sentence summary
- `match`: the specific symbol/pattern to remove or fix (empty string `""` if not applicable)

If the scan produces zero findings, do **not** write the JSONL file and do **not** call proactive-cleanup.sh.

After the JSONL file is written, invoke proactive-cleanup.sh **non-blocking** (so the skill does not wait for it to finish):

```bash
SCAN_DATE=$(TZ=America/New_York date +%Y-%m-%d)
JSONL="$HOME/.openclaw/agents/ranveer/data/audit/backlog-scan-${SCAN_DATE}.jsonl"
LOG="$HOME/.openclaw/cron/runs/proactive-cleanup-${SCAN_DATE}-$(date -u +%H%M%S).log"
bash "$HOME/.openclaw/agents/ranveer/scripts/proactive-cleanup.sh" \
  --input "$JSONL" \
  >> "$LOG" 2>&1 &
```

Log the PID for traceability but do not wait for it. Continue immediately to write the HTML brief and post to Slack.

## Briefing message format

Write HTML brief to `ranveer-reports-private/briefs/ranveer-backlog-<ISO-timestamp>.html`. Then post ONE Slack message to `#code` (channel `C0AM06M0JE8`).

**Required format** — content lines first, then the interactive directive on its own line:

```
<inline summary: problem in 1-2 lines, recommendation in 1 line>
approve to start the build, or skip to wait. [[slack_buttons: Approve:ranveer-go:primary, Skip:ranveer-skip]]
```

Rules:
- **Inline summary mandatory** — Sameer doesn't open links, so the gist must be in the message body. A link to the HTML brief is OPTIONAL and supplemental, only if the proposal needs more detail than 3 lines.
- **HEAD-check any URL** before posting. `gs://` is forbidden — must be HTTPS.
- The `[[slack_buttons:]]` directive renders Block Kit buttons via OpenClaw's interactive replies feature. The `Approve:ranveer-go:primary` button click routes through bolt-app.ts → `handleRanveerGo` → `autonomous-batch.sh`. The text "ranveer go" reply still works as a fallback.
- Thread replies are reserved for backlog items #2 and #3 on request.

## Hard rules

- **Never edit files** — this skill is read-only. The autonomous build happens only after `ranveer go`.
- **Never post if scope guard would escalate** — pre-check against `src/ranveer-scope-guard.ts` so briefings only surface work Ranveer could actually execute.
- **Never bypass dryrun** — read `jq -r '.dryrun' $HOME/.openclaw/agents/ranveer/autonomy.json`. If true, include `(dry-run)` in the briefing message so Sameer knows a `ranveer go` won't actually merge.
- **Never double-post** — check `$HOME/.openclaw/agents/ranveer/data/audit/autonomous-runs.jsonl` for an open briefing with no merge/escalation outcome since last post; if one exists, exit 0.

## Output contract

On success: single Slack message posted, HTML brief written, audit row `{stage:"briefing",status:"posted",...}` appended to `$HOME/.openclaw/agents/ranveer/data/audit/autonomous-runs.jsonl`.

On backlog empty across all repos: post `Backlog empty across all repos. Standing by.` and exit 0.

On autonomy disabled: no Slack post, audit row `{stage:"briefing",status:"skipped",reason:"autonomy_disabled"}`.

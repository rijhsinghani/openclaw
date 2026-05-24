---
name: ranveer-backlog-scan
description: 'Scan all managed repos (studio-os, investment-accounting, content-engine, .openclaw) for hardening work — dead code, ready-to-merge PRs, stale branches > 14 days, coverage gaps — and post a single briefing message to #code with the top proposal. Triggered by cron (ranveer-backlog-scan-am / -pm) or on-demand when Ranveer asks to run it. Use when scanning Ranveer''s open backlog for next-best work. Triggers include: ''ranveer backlog scan'', ''backlog scan'', ''what is next for ranveer'', ''pick a backlog item''.'
metadata:
  openclaw:
    emoji: 🔍
    requires:
      bins:
      - bash
      - gh
      - git
      - jq
      - node
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
{
  "tier": "trivial",
  "repo": "/abs/path/to/repo",
  "path": "repo-relative/file.ext",
  "category": "unused-import",
  "description": "One-sentence summary of the issue",
  "match": "optional symbol or pattern, empty string if N/A"
}
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

Post ONE Slack message to `#code` (channel `C0AM06M0JE8`). The message body IS the primary deliverable — it must stand on its own without any link.

### Inline body (mandatory, every tier)

Every briefing MUST include, in the top-level Slack message itself:

1. **Severity emoji counts** — one short line summarizing the scan, e.g. `🔴 0 critical · 🟡 2 medium · 🟢 7 trivial across 4 repos`.
2. **Top 3 findings** — one line each, each containing:
   - the repo name + repo-relative file path (e.g. `studio-os apps/client-portal/lib/utils.ts`)
   - a 1-line plain-English description of the issue
   - a 1-line plain-English action ("remove unused import", "delete dead export `foo()`", etc.)
3. **Recommendation** — the single next step, in business English.

### Tier-gated button emission — DECISION RULE

The button directive is REQUIRED when ANY of these are true, and FORBIDDEN otherwise:

- The severity line includes any 🔴 critical findings (`critical > 0`)
- The severity line includes any 🟡 medium findings (`medium > 0`)
- The top proposal's JSONL `tier` is `medium` or `large`

If the severity line is 🔴 0 · 🟡 0 and the top proposal's tier is `trivial` or `small` → no buttons (auto-ship path).

Severity-emoji ↔ tier mapping (use this — do not invent new severity names):

- 🔴 critical ⇒ `tier=large` (architectural, auth, payment, DB migration, placeholder business logic)
- 🟡 medium ⇒ `tier=medium` (multi-file refactor, API signature change, test restructure)
- 🟢 trivial ⇒ `tier=trivial` OR `tier=small` (unused imports, dead exports, lint warnings, dep bumps, duplicate utils)

Only these two output variants are allowed — no third variant.

**Variant A — auto-ship (no buttons).** Use when 🔴=0 AND 🟡=0 AND top tier ∈ {trivial, small}:

Ranveer dispatches the fix autonomously (`proactive-cleanup.sh` path — CodeRabbit-gated, CI-gated). The briefing message is a notification, not a gate.

```
<severity line>
<top 3 findings, one per line>
Auto-shipping the top finding now (trivial/small, safe-change path). Will reply in thread with PR link when CodeRabbit + CI are green.
```

On merge, post a thread reply to the briefing: `✅ shipped PR #NNN — <1-line summary>`.

**Variant B — approval required (Block Kit buttons mandatory).** Use when 🔴>0 OR 🟡>0 OR top tier ∈ {medium, large}:

Emit the same inline summary in the streaming reply (for visibility), but the **authoritative Block Kit post with buttons** MUST be produced by `post-scan-result.sh`, not by the deprecated `[[slack_buttons: ...]]` directive. (Why: the directive only compiles through `slackOutbound.sendPayload` / `normalizePayload`, which Ranveer's scan replies bypass. Block Kit buttons never rendered for months until 2026-04-24 when the architectural path below was introduced.)

Steps for Variant B:

1. Write the scan summary JSON to `~/.openclaw/data/ranveer/scan-<ISO>.json` where `<ISO>` is `$(date -u +%Y-%m-%dT%H%M%SZ)`. Schema:

   ```json
   {
     "scan_date": "2026-04-24",
     "scan_id": "2026-04-24T123000Z",
     "severity": { "critical": 0, "medium": 2, "trivial": 7 },
     "repos_scanned": [
       "studio-os",
       "investment-accounting",
       "content-engine",
       ".openclaw"
     ],
     "top_findings": [
       {
         "tier": "medium",
         "repo": "studio-os",
         "path": "apps/client-portal/lib/utils.ts",
         "description": "3 unused exports",
         "action": "remove unused exports"
       }
     ],
     "recommendation": "Approve to start the build, or Defer to skip this cycle.",
     "requires_approval": true
   }
   ```

2. Invoke the poster — blocking, exit code determines success:

   ```bash
   SCAN_JSON="$HOME/.openclaw/data/ranveer/scan-$(date -u +%Y-%m-%dT%H%M%SZ).json"
   # (write $SCAN_JSON with the schema above)
   bash "$HOME/.openclaw/agents/ranveer/scripts/post-scan-result.sh" "$SCAN_JSON"
   ```

3. The streaming inline reply (the skill's own LLM output) should still include the severity line + top 3 findings + recommendation for visibility. Do NOT include `[[slack_buttons: ...]]` — that directive is deprecated and renders as literal text.

The inline streaming reply and the `post-scan-result.sh` Block Kit post are two messages: the first is the conversational reply (no buttons), the second is the authoritative decision-gate post with Approve/Defer buttons (`action_id`s `ranveer-go` / `ranveer-skip` registered in `openclaw.json` → `plugins.entries["slack-action-router"].config.handlers`).

Self-check before completing: if the severity line contains 🔴 or 🟡 AND `post-scan-result.sh` exited non-zero (and not exit 3 which is the auto-ship signal), the skill run is INVALID — the approval gate did not post. Fail loudly; do NOT silently drop the gate.

### Overflow

- If the body exceeds ~3000 chars, post the severity line + top-3 top-level and put repo-by-repo detail as sequential thread replies.
- An HTML brief at `ranveer-reports-private/briefs/...` MAY be generated for audit trail. It is NEVER the primary deliverable and its path is NEVER posted top-level.
- If additional context genuinely cannot fit in threaded replies (rare — rendered HTML only), generate a 24h signed HTTPS URL via `gcloud storage sign-url <gs://...> --duration=24h` and post the HTTPS URL. NEVER the raw `gs://` URI.

### Hard rules on URLs

- `gs://` is forbidden in any Slack message, top-level or thread, regardless of context. Rule B of SOUL.md governs.
- HTTPS URLs must be HEAD-checked (200 response) before posting.
- Block Kit Approve/Defer buttons are posted by `post-scan-result.sh` (see Variant B above), NOT by the deprecated `[[slack_buttons:]]` directive. The button click flows through the gateway's `slack-action-router` (configured in `openclaw.json`) → spawns `openclaw agent --agent ranveer --message <autonomous-batch prompt>`. The text "ranveer go" reply still works as a fallback for channels where the buttons didn't render.
- Thread replies are reserved for findings #2+ on request, and for the `✅ shipped PR #NNN` confirmation on auto-ship.

## Hard rules

- **Never edit files** — this skill is read-only. The autonomous build happens only after `ranveer go`.
- **Never post if scope guard would escalate** — pre-check against `src/ranveer-scope-guard.ts` so briefings only surface work Ranveer could actually execute.
- **Never bypass dryrun** — read `jq -r '.dryrun' $HOME/.openclaw/agents/ranveer/autonomy.json`. If true, include `(dry-run)` in the briefing message so Sameer knows a `ranveer go` won't actually merge.
- **Never double-post** — check `$HOME/.openclaw/agents/ranveer/data/audit/autonomous-runs.jsonl` for an open briefing with no merge/escalation outcome since last post; if one exists, exit 0.

## Output contract

On success: single Slack message posted, HTML brief written, audit row `{stage:"briefing",status:"posted",...}` appended to `$HOME/.openclaw/agents/ranveer/data/audit/autonomous-runs.jsonl`.

On backlog empty across all repos: post `Backlog empty across all repos. Standing by.` and exit 0.

On autonomy disabled: no Slack post, audit row `{stage:"briefing",status:"skipped",reason:"autonomy_disabled"}`.

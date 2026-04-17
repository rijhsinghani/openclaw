# Ranveer Memory

## Engineering Goals (Q2 2026)

- All 3 repos must pass CI: lint, typecheck, tests
- Zero stale GitHub PRs (>48h without review)
- Zero silent failures — every error surfaces to Slack
- Infrastructure costs tracked monthly
- Every scan cycle proposes a 1% improvement
- GSD workflow compliance on all code changes

## Business Goals I Support

- **Booking app:** 48-hour gallery delivery SLA, 100% booking-to-contract automation, zero missed follow-ups
- **Content pipeline:** 3 reels/week, 5 social posts/week, weekly YouTube publish
- **Financial tracker:** Accounts reconciled within 24h, monthly P&L by 5th of month

## Cost Architecture (NON-NEGOTIABLE)

- GLM 5.1 for all chat and scanning (~$0)
- Opus for brain decisions only — capped at 1-2 calls per cycle
- Codex for all coding — $0 marginal cost (subscription)
- Target: near-zero marginal cost per scan cycle
- Never use Claude/Opus for tasks GLM can handle

## What I Learned

- OpenClaw's `message send --interactive` does NOT render Slack Block Kit buttons. Use direct Slack API via `slack-post-as.sh` instead.
- App-level Slack icon overrides per-message `icon_url`. Direct API with bot token + username + icon_url works.
- Blocker IDs must be content-stable (repo:category:path), not position-based. Position-based IDs drift between scans.
- Schema validation between pipeline stages prevents silent data corruption.
- call-opus-advisor.sh must exit 0 (skip) on zero-blocker runs, not exit 1 (fail).
- Voice gate (voice-gate.py) enforces output quality more reliably than SOUL.md rules alone.

## Phase 25 Shipped (2026-04-11)

Full re-architecture complete:
- Stable blocker IDs, schema validation, scanner regex fixes
- Concise Slack summaries with Block Kit approve/skip/details buttons
- Ranveer avatar on every message via direct Slack API
- 3-agent split: GLM chat, Opus brain, Codex coder
- Error replies on all 7 failure paths
- Voice gate, cron sanity, reply poller, decision reconciler
- Progress heartbeat during Codex execution
- All 10 e2e verification checks passed

## Standing Orders — Proactive Behavior (2026-04-12)

- **mypy errors are auto-fix eligible** — run fixes without being asked. Don't wait for Sameer to prompt.
- Sameer: "proactively fix it next time too without me asking" (2026-04-12 re: mypy overnight task timeout)
- After any overnight/scheduled task that involves type checking: if errors found, immediately spawn a fix subagent
- mypy check commands:
  - investment-accounting: `cd ~/investment-accounting && venv/bin/mypy backend/ domains/ trackers/ --ignore-missing-imports --exclude '(venv|\.venv|__pycache__)'`
  - content-engine: `cd ~/content-engine && mypy backend/ --ignore-missing-imports --exclude '(venv|\.venv|__pycache__|\.claude)'`

## Promoted From Short-Term Memory (2026-04-13)

<!-- openclaw-memory-promotion:memory:memory/2026-04-09.md:1:29 -->
- # 2026-04-09 — ranveer daily notes ## Daily Repo Scan (20:51 EDT) 3-repo scan for TODO/FIXME/HACK/stubs. Excluded: test/, tests/, node_modules/, dist/, venv/, .venv/, __pycache__/, .claude/, .next/, build/, coverage/. ### Counts | Repo | TODO/FIXME/HACK | Stub `pass` | Total | |------|-----------------|-------------|-------| | studio-os | 13 | 82 | 95 | | content-engine | 1 | 30 | 31 | | investment-accounting | 11 | 77 | 88 | | **Total** | **25** | **189** | **214** | ### Top 5 Findings (by severity) 1. **SEV-1** `studio-os/packages/queues/src/workers/video.worker.ts` — 6 consecutive TODOs (lines 160, 177, 194, 209, 227, 242). Entire worker is a stub with no Python API integration. No downloads, assembly, render, upload, email, or metadata work implemented. 2. **SEV-1** `investment-accounting/backend/services/data_source_orchestrator.py:579` — TODO: statement parsing not implemented. Core data ingestion is missing. 3. **SEV-2** `investment-accounting/trackers/tax_scenario_analyzer.py:360` — TODO: QuickBooks API integration not built. Tax analysis relies on manual data. 4. **SEV-2** `investment-accounting/trackers/tax_scenario_qb_integration.py:131` — TODO: estimated_payments hardcoded to 0, no database pull. Financial projections are inaccurate. 5. **SEV-2** `studio-os/infra/cloud-run-jobs/video-render/render_video.py:170` — TODO: segment trimming not implemented. Render pipeline incomplete. ### Notes - studio-os `video.worker.ts` is the biggest single risk — 6 stubs in one file, entire workflow unimplemented [score=0.932 recalls=42 avg=0.679 source=memory/2026-04-09.md:1-29]
<!-- openclaw-memory-promotion:memory:memory/2026-04-10.md:1:31 -->
- # 2026-04-10 — ranveer daily notes ## Daily Repo Scan (11:03 EDT) 3-repo scan for TODO/FIXME/HACK/stubs. Excluded: test/, tests/, node_modules/, dist/, venv/, .venv/, __pycache__/, .claude/, .next/, build/, coverage/. ### Counts | Repo | TODO/FIXME/HACK | Stub `pass` | Total | |------|-----------------|-------------|-------| | studio-os | 17* | 82 | 99 | | content-engine | 1 | 29 | 30 | | investment-accounting | 11 | 79 | 90 | | **Total** | **29** | **190** | **219** | *studio-os TODO count includes 4 test/qa-file matches (qa.test.ts, qa.js, CheckoutFlow.test.tsx, edge-cases.test.ts) and 1 vitest.config.ts exclude comment. Real production TODOs: 12. ### Delta vs 2026-04-09 | Repo | TODOs (prev) | TODOs (now) | Δ | Pass (prev) | Pass (now) | Δ | |------|-------------|-------------|---|-------------|------------|---| | studio-os | 13 | 17* | +4 | 82 | 82 | 0 | | content-engine | 1 | 1 | 0 | 30 | 29 | -1 | | investment-accounting | 11 | 11 | 0 | 77 | 79 | +2 | *Count methodology differs — previous scan may have excluded test files more aggressively. Net new production TODOs: ~4 in studio-os (checkout, photo-workflow, slack handler, video-render). ### Top 5 Findings (by severity) 1. **SEV-1** `studio-os/packages/queues/src/workers/video.worker.ts` — 6 consecutive TODOs (lines 160, 177, 194, 209, 227, 242). Entire worker is a stub with no Python API integration. **Unchanged from yesterday.** [score=0.904 recalls=21 avg=0.667 source=memory/2026-04-10.md:1-31]
<!-- openclaw-memory-promotion:memory:memory/2026-04-10.md:26:51 -->
- *Count methodology differs — previous scan may have excluded test files more aggressively. Net new production TODOs: ~4 in studio-os (checkout, photo-workflow, slack handler, video-render). ### Top 5 Findings (by severity) 1. **SEV-1** `studio-os/packages/queues/src/workers/video.worker.ts` — 6 consecutive TODOs (lines 160, 177, 194, 209, 227, 242). Entire worker is a stub with no Python API integration. **Unchanged from yesterday.** 2. **SEV-1** `investment-accounting/backend/services/data_source_orchestrator.py:583` — TODO: statement parsing not implemented. Core data ingestion is missing. **Unchanged.** 3. **SEV-2** `investment-accounting/trackers/tax_scenario_analyzer.py:360` — TODO: QuickBooks API integration not built. Tax analysis relies on manual data. **Unchanged.** 4. **SEV-2** `investment-accounting/trackers/tax_scenario_qb_integration.py:131` — TODO: estimated_payments hardcoded to 0, no database pull. Financial projections are inaccurate. **Unchanged.** 5. **SEV-2** `studio-os/packages/gcp-functions/src/handlers/slack.ts:255` — TODO: Integrate with RPV Agent for AI responses. **New since yesterday.** ### studio-os Stub Pass Hotspots (82 total) - `apps/video-pipeline-adk/` — 39 stubs across 9 files (orchestrator, tools, agents, services). The entire ADK pipeline is scaffolded. ### investment-accounting Stub Pass Hotspots (79 total) - `domains/wealth/tax_dashboard.py` — 3 stubs - `domains/bookkeeping/year_end/validators.py` — 3 stubs - `backend/domains/bookkeeping_ops_domain.py` — 3 stubs - `backend/domains/base_domain.py` — 3 stubs ### Notes [score=0.901 recalls=20 avg=0.657 source=memory/2026-04-10.md:26-51]
<!-- openclaw-memory-promotion:memory:memory/2026-04-09.md:24:32 -->
- 4. **SEV-2** `investment-accounting/trackers/tax_scenario_qb_integration.py:131` — TODO: estimated_payments hardcoded to 0, no database pull. Financial projections are inaccurate. 5. **SEV-2** `studio-os/infra/cloud-run-jobs/video-render/render_video.py:170` — TODO: segment trimming not implemented. Render pipeline incomplete. ### Notes - studio-os `video.worker.ts` is the biggest single risk — 6 stubs in one file, entire workflow unimplemented - investment-accounting has 7 TODOs in tax/financial code — accuracy risk - content-engine is cleanest with only 1 TODO - Large `pass` stub counts in studio-os (82) and investment-accounting (77) suggest many exception-swallowing or unimplemented methods [score=0.889 recalls=39 avg=0.643 source=memory/2026-04-09.md:24-32]
<!-- openclaw-memory-promotion:memory:memory/2026-04-10.md:42:55 -->
- - `apps/video-pipeline-adk/` — 39 stubs across 9 files (orchestrator, tools, agents, services). The entire ADK pipeline is scaffolded. ### investment-accounting Stub Pass Hotspots (79 total) - `domains/wealth/tax_dashboard.py` — 3 stubs - `domains/bookkeeping/year_end/validators.py` — 3 stubs - `backend/domains/bookkeeping_ops_domain.py` — 3 stubs - `backend/domains/base_domain.py` — 3 stubs ### Notes - **No SEV-1 items resolved** since yesterday — video.worker.ts and data_source_orchestrator.py remain the highest-risk items. - studio-os video-pipeline-adk has the densest stub concentration (39 `pass` statements in one directory). - content-engine is cleanest — only 1 TODO and 29 stubs. - investment-accounting stubs slightly increased (+2). [score=0.868 recalls=19 avg=0.655 source=memory/2026-04-10.md:42-55]

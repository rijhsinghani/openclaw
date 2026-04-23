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
  - investment-accounting: cd ~/investment-accounting && venv/bin/mypy backend/ domains/ trackers/ --ignore-missing-imports --exclude '(venv|\.venv|__pycache__)'
  - content-engine: cd ~/content-engine && mypy backend/ --ignore-missing-imports --exclude '(venv|\.venv|__pycache__|\.claude)'

## Promoted From Short-Term Memory (2026-04-18)

- ## 2026-04-13 17:35 ET — Pre-compaction memory flush - Workspace: /Users/sameerrijhsinghani/.openclaw/workspace-ranveer. - Slack context: channel C0AM06M0JE8, provider Slack, use Slack mrkdwn for any channel replies. For this flush, normally reply NO_REPLY unless there is a concrete user-facing result. - Standing orders from AGENTS.md for ranveer: long scan reports/audits/fix diffs over 15 lines must be published with publish-deliverable --persona=ranveer --category=reports --file=/tmp/ranveer-report-<slug>-<YYYYMMDD-HHMMSS>.html --classification=internal-only; return only the gs:// path plus 3-line Slack summary, not raw Slack walls. - Auto-fix policy: only low-risk hygiene like unused imports, confirmed dead code, patch dependency bumps; never auto-fix files involving auth, payment, stripe, clerk, webhook, billing, secret, migration, schema, or router/handler files. Medium risk requires Slack approval; high risk is report-only. - Remediation flow: branch ranveer/<repo>/<description>, commit fix(scope): description, run run-ci skill, then use ship skill. Never call git push, gh pr create, or gh pr merge directly; ship.sh owns push/PR/CodeRabbit/merge audit/Slack messaging. - Memo reply handler v2: for #claude memo-thread replies, run scripts/parse-slack-reply.py <raw text> piped into scripts/handle-decision.sh with env ENG_HYGIENE_THREAD_TS, ENG_HYGIENE_MEMO_ID, and ENG_HYGIENE_ACTOR; post stdout status/why text back to the Slack thread. Tests live at agents/ranveer/tests/test-reply-parser.sh. [score=0.830 recalls=4 avg=0.717 source=memory/2026-04-13.md:1-8]

## Promoted From Short-Term Memory (2026-04-21)

- ## PR #652 CodeRabbit Fixes (20:21 EDT) - Fixed 3 CodeRabbit comments on studio-os PR #652: 1. jsor: -> jsr: in send-gallery-notification (broken bundling) 2. Relative import paths ../../../../ -> ../../../ in both Supabase functions 3. Moved render(PostEventEmail(...)) inside try block in send-post-event-email - Type-check pass, Lint pass - Pushed to branch, ship.sh ran. CodeRabbit re-review requested. - Also added backups/ to .gitignore to fix dirty tree preflight failure. - Ship status: escalated (waiting for CodeRabbit re-review) [score=0.933 recalls=12 avg=0.713 source=memory/2026-04-13.md:403-416]

## Silent Replies

When you have nothing to say, respond with ONLY: NO_REPLY
⚠️ Rules:
- It must be your ENTIRE message — nothing else
- Never append it to an actual response (never include "NO_REPLY" in real replies)
- Never wrap it in markdown or code blocks
❌ Wrong: "Here's help... NO_REPLY"
❌ Wrong: "NO_REPLY"
✅ Right: NO_REPLY



## Promoted From Short-Term Memory (2026-04-22)

- **Subprocess Output Handling Rule:** When a subprocess handles all its own outputs, return immediately and end the session — holding it open risks LLM timeouts on idle waits. Trust the subprocess and exit; do not wait for completion if it manages its own logging/reporting.


## Promoted From Short-Term Memory (2026-04-23)

<!-- openclaw-memory-promotion:memory:memory/archive/2026-04-22.md:1:20 -->
- --- Memory Compact: 2026-04-22 16:04 EDT --- ## Session Stats - Date: 2026-04-22 - Type: Maintenance / Compact - Triggered by: sameerrijhsinghani ## Files Before Compact EOF ls -la archive/ >> archive/2026-04-22.md 2>/dev/null || true cat .dreams/short-term-recall.json | head -5 >> archive/2026-04-22.md 2>/dev/null || true echo " ## Compact Actions" >> archive/2026-04-22.md echo "- Consolidated daily files" >> archive/2026-04-22.md echo "- Trimmed JSON histories (keeping last 7 days)" >> archive/2026-04-22.md echo "- Removed stale logs" >> archive/2026-04-22.md cat archive/2026-04-22.md [score=0.852 recalls=6 avg=0.731 source=memory/archive/2026-04-22.md:1-20]

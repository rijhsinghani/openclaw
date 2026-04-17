# ranveer — Heartbeat Checks

## Schedule: Every 12 hours, 8am-10pm ET

Heartbeats are lightweight — only check for critical issues.
Full scanning happens in the weekly report and on-demand triggers.

- [ ] Critical vulnerability check: `npm audit` + `pip-audit` (CRITICAL severity only)
      → If any CRITICAL CVE: flag P1 immediately, post to Slack

- [ ] CI break detection: run typecheck + lint only (not full test suite)
      → If any repo fails: flag P1, post to Slack

- [ ] If all checks pass: HEARTBEAT_OK (no Slack post, no metrics update)

## What Heartbeat Does NOT Do

- Does NOT scan for TODOs/FIXMEs (weekly handles this)
- Does NOT check coverage delta (weekly handles this)
- Does NOT run full test suites (too expensive for routine checks)
- Does NOT check stale branches (weekly handles this)

## Suppression

- If no CRITICAL CVEs AND no CI failures: stay completely silent

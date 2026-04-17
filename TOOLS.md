# ranveer — Tools Reference

## Repos

| App               | Path                        | Stack                       |
| ----------------- | --------------------------- | --------------------------- |
| Booking app       | ~/studio-os                 | TypeScript, Next.js, vitest |
| Content pipeline  | ~/content-engine            | Python, FastAPI, pytest     |
| Financial tracker | ~/dev/investment-accounting | Python, pytest              |

## GitHub

Owner: `rijhsinghani` (not sameerrijhsinghani)

- PRs: `gh pr list --repo rijhsinghani/<repo> --state open`
- CI: `gh run list --repo rijhsinghani/<repo> --limit 3`

## Excludes (ALWAYS use)

TS: `--exclude-dir=node_modules --exclude-dir=dist --exclude-dir=build --exclude-dir=.next --exclude-dir=coverage --exclude-dir=.turbo --exclude-dir=.git --exclude-dir=.claude`

PY: `--exclude-dir=venv --exclude-dir=.venv --exclude-dir=env --exclude-dir=__pycache__ --exclude-dir=.pytest_cache --exclude-dir=.git --exclude-dir=.claude`

## CI (always pipe through tail)

- Booking: `cd ~/studio-os && pnpm type-check 2>&1 | tail -5 && pnpm lint 2>&1 | tail -10`
- Content: `cd ~/content-engine && ruff check . --exclude=.venv,venv,env 2>&1 | tail -10`
- Finance: `cd ~/dev/investment-accounting && ruff check . --exclude=.venv,venv,env 2>&1 | tail -10`

## Posting to Slack

**Always use this exact command:**

```bash
openclaw message send --channel slack --target C0AM06M0JE8 -m "your message here"
```

NEVER use `openclaw slack` — that command does not exist.

## Metrics

- Daily: ~/.openclaw/agents/ranveer/data/hygiene-metrics.jsonl
- Baseline: ~/.openclaw/agents/ranveer/data/coverage-baseline.json

## Triggers

- `@ranveer scan <repo>` — full scan
- `@ranveer ci <repo>` — CI checks
- `@ranveer audit` — security/dependency audit
- `@ranveer debt` — weekly report on demand
- `@ranveer approve <id>` — execute approved fix

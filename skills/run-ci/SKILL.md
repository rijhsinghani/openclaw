---
name: run-ci
description: "Run local CI checks before pushing or shipping. All checks you touch must pass. Pre-existing failures don't block you."
metadata:
  openclaw:
    emoji: "✅"
    requires:
      bins: ["pnpm", "ruff"]
---

# Run CI — Local Quality Checks

## Policy

**Your changes must not break CI.** If a check was already failing before your change, note it but don't let it block your fix.

## Commands (always pipe through tail)

### Booking app (studio-os)
```bash
cd ~/studio-os && pnpm type-check 2>&1 | tail -5 && pnpm lint 2>&1 | tail -10
```

### Content pipeline (content-engine)
```bash
cd ~/content-engine && ruff check . --exclude=.venv,venv,env 2>&1 | tail -10
```

### Financial tracker (investment-accounting)
```bash
cd ~/dev/investment-accounting && ruff check . --exclude=.venv,venv,env 2>&1 | tail -10
```

## If CI Fails

- Error in YOUR diff: fix it before pushing
- Pre-existing error (not your change): note in Slack report, push anyway
- NEVER use `--no-verify` or skip hooks

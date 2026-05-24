---
name: ranveer-attention-probe
description: 'Weekly self-test that measures how well Ranveer can recall rules from the top, middle, and tail of his own SOUL.md. Bundles 5 questions into one agent spawn, scores keyword presence, posts a tiered scorecard to #code. Alerts if any tier drops below 80% (signals attention decay / rule drift). Use when invoked during Ranveer''s heartbeat cycle. Triggers include: ''ranveer attention probe'', ''ranveer idle cycle'', ''check what ranveer should do next'', ''ranveer attention''.'
metadata:
  openclaw:
    emoji: 🧠
    requires:
      bins:
      - bash
      - python3
---

# attention-probe — weekly recall self-test

Long prompts suffer attention decay: rules at byte 25K of a bootstrap
are reliably ignored even when the bootstrap isn't truncated. We caught
Ranveer violating a rule that *was* in his SOUL — just in the wrong
byte range. This probe is the canary: it tests recall from each tier of
the playbook so we see the regression before a user-visible incident.

## How it works

1. Read `~/.openclaw/data/attention-probes/ranveer-probes.yaml` — five
   probe questions, each anchored to a byte range of the live SOUL
   (top-3K, mid-3-6K, mid-6-9K, tail-9K+).
2. Bundle all five into a SINGLE `openclaw agent` spawn (5× cheaper
   than one spawn per question).
3. Parse the agent's reply, score each probe by `expected_keywords`
   presence, average by tier.
4. Return a JSON scorecard for the cron payload to format for Slack.

## Call

```bash
bash ~/.openclaw/scripts/attention-probe.sh ranveer
```

Output is a JSON blob with per-probe scores and tier averages.

## Cron wiring

The weekly cron job "Ranveer Attention Probe" (Mon 09:07 ET) runs this
skill, parses the JSON, and posts ONE line to #code (C0AM06M0JE8):

```
Attention probe: top=100%, mid=80%, tail=60% — tail-section recall is low, refactor recommended.
```

Any tier < 80% → post an escalation line: "⚠️ SOUL.md needs refactor —
rule density or ordering has drifted." The cron message body does the
formatting; this skill just produces the raw scores.

## Tuning the probes

Probe questions and expected keywords live in
`~/.openclaw/data/attention-probes/ranveer-probes.yaml`. Edit when the
SOUL gets restructured — byte ranges must match the post-refactor
layout. Run this audit after any SOUL edit:

```bash
for kw in "Identity" "dispatch-coding" "ship.sh" "consult-knowledge"; do
  python3 -c "import sys;d=open(sys.argv[1],'rb').read();k=sys.argv[2].encode();print(f'{sys.argv[2]:<30} byte {d.find(k)}')" \
    ~/.openclaw/workspace-ranveer/SOUL.md "$kw"
done
```

## Why we bundle

5 questions × 2 agents × weekly via `openclaw agent --agent ...` would
mean 520 spawns/year. One bundled spawn per agent cuts that 5× to ~100
spawns/year. The bundled prompt asks for numbered short answers, which
is cheap to score.

# workspace-ranveer/ — Ranveer's Active Workspace

This directory is gitignored (ephemeral agent workspace). Holds Ranveer's live skills, memory, and working context across repos.

Key subdirs:
- `skills/` — engineering skills (ranveer-task-spec, ranveer-post-ship-wiring, gsd-*, ship, etc.)
- `memory/` — session memory and working context
- `config/` — workspace-level MCP and tool configuration

Note on skills: 6 identical skills were removed from this workspace in Phase 2 cleanup (2026-04-17); canonical copies live in workspace-anisha/skills/. Two divergent skills remain unresolved (Sameer to decide): attention-probe and consult-knowledge.

**Debug tip:** To check active skills: `ls workspace-ranveer/skills/`. Recent sessions: `ls -lt agents/ranveer/sessions/ | head -5`.

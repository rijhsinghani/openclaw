# handoff-complete validation rules

The dispatcher rejects the completion if any of the following are true:

1. Missing any of the 5 numbered prefixes:
   - `1. What I shipped:`
   - `2. Where it landed:`
   - `3. Handoff this closes:`
   - `4. Anything Sameer needs to do:`
   - `5. Next step:`
2. Any field has fewer than 4 words, except:
   - line 2 may be a short destination phrase such as `the skills folder`
   - line 3 may be a bare timestamp for the original handoff
   - line 4 may be plain `no`
   - line 5 may be `none, closed`
3. Any field contains placeholders such as `<...>`, `TODO`, `TBD`, `...`, `fill in`, `foo`, or `bar`
4. Any field leaks file paths, URLs, repo-relative paths, line references, stack traces, or exit/status codes
5. `--from` is not a supported active closer (`ranveer`, `anisha`, `nisha`, `shalini`)
6. No matching OPEN handoff exists in `~/.openclaw/data/handoffs/log.jsonl`
7. More than one OPEN handoff matches and no explicit `--handoff-timestamp` disambiguates it

Additional matching guardrails:

- The completion skill only closes rows without `completed_at`
- The row must have been handed TO the closer (`row.to == --from`)
- If the row already has `completed_at`, the dispatcher refuses to double-close it

Outbound posting rules:

- The completion text is run through `outbound-slack-validator` rewrite logic before posting
- Rewrites are allowed; a validator cancel is treated as a dispatch failure
- The same sanitized text is posted to the originating channel and the closer's own home channel

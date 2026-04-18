#!/usr/bin/env bash
# handoff-complete/dispatch.sh
# Validates a 5-line handoff completion, updates the matching open handoff row,
# rewrites the outbound text through outbound-slack-validator logic, and posts
# the visible completion card to both the originating channel and the closer's
# own channel.

set -euo pipefail

HANDOFF_LOG="${HANDOFF_LOG:-$HOME/.openclaw/data/handoffs/log.jsonl}"
OPENCLAW_BIN="${OPENCLAW_BIN:-$(command -v openclaw || echo /opt/homebrew/bin/openclaw)}"
OPENCLAW_CONFIG="${OPENCLAW_CONFIG:-$HOME/.openclaw/openclaw.json}"
VALIDATOR_LIB="${VALIDATOR_LIB:-$HOME/.openclaw/plugins/outbound-slack-validator/lib.mjs}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

err() { printf 'handoff-complete: %s\n' "$*" >&2; }

FROM=""
MSG_FILE=""
HANDOFF_TIMESTAMP=""
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) FROM="${2:-}"; shift 2 ;;
    --message-file) MSG_FILE="${2:-}"; shift 2 ;;
    --handoff-timestamp) HANDOFF_TIMESTAMP="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN="true"; shift ;;
    -h|--help)
      sed -n '2,18p' "$0"
      exit 0
      ;;
    *)
      err "unknown arg: $1"
      exit 2
      ;;
  esac
done

[[ -z "$FROM" ]] && { err "--from is required"; exit 2; }
[[ -z "$MSG_FILE" ]] && { err "--message-file is required"; exit 2; }
[[ ! -r "$MSG_FILE" ]] && { err "cannot read message file: $MSG_FILE"; exit 2; }
[[ ! -f "$HANDOFF_LOG" ]] && { err "handoff log not found: $HANDOFF_LOG"; exit 3; }
[[ ! -f "$OPENCLAW_CONFIG" ]] && { err "openclaw config not found: $OPENCLAW_CONFIG"; exit 4; }
[[ ! -f "$VALIDATOR_LIB" ]] && { err "validator lib not found: $VALIDATOR_LIB"; exit 4; }

case "$FROM" in
  ranveer|anisha|nisha|shalini) ;;
  *)
    err "invalid --from: $FROM"
    exit 3
    ;;
esac

MSG="$(cat "$MSG_FILE")"
[[ -z "${MSG// /}" ]] && { err "message is empty"; exit 3; }

get_field() {
  local prefix="$1"
  printf '%s\n' "$MSG" | awk -v prefix="$prefix" '
    index($0, prefix) == 1 {
      print substr($0, length(prefix) + 1)
      found = 1
      exit
    }
    END { if (!found) exit 1 }
  '
}

P1='1. What I shipped: '
P2='2. Where it landed: '
P3='3. Handoff this closes: '
P4='4. Anything Sameer needs to do: '
P5='5. Next step: '

F1="$(get_field "$P1" || true)"
F2="$(get_field "$P2" || true)"
F3="$(get_field "$P3" || true)"
F4="$(get_field "$P4" || true)"
F5="$(get_field "$P5" || true)"

for i in 1 2 3 4 5; do
  val_var="F${i}"
  val="${!val_var}"
  if [[ -z "${val// /}" ]]; then
    err "validation failed: line ${i} missing or empty"
    exit 3
  fi
done

count_words() { printf '%s\n' "$1" | awk '{ print NF }'; }

for i in 1; do
  val_var="F${i}"
  val="${!val_var}"
  wc_val="$(count_words "$val")"
  if [[ "$wc_val" -lt 4 ]]; then
    err "validation failed: line ${i} is too short (${wc_val} words)"
    err "  content: $val"
    exit 3
  fi
done

F2_WORDS="$(count_words "$F2")"
if [[ "$F2_WORDS" -lt 2 ]]; then
  err "validation failed: line 2 is too short (${F2_WORDS} words). Name the destination in plain English."
  err "  content: $F2"
  exit 3
fi

F3_WORDS="$(count_words "$F3")"
if [[ "$F3_WORDS" -lt 4 ]]; then
  if ! printf '%s' "$F3" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}([T ][0-9]{2}:[0-9]{2}(:[0-9]{2})?Z?)?$'; then
    err "validation failed: line 3 is too short (${F3_WORDS} words). Use a topic phrase or original timestamp."
    err "  content: $F3"
    exit 3
  fi
fi

F4_LC="$(printf '%s' "$F4" | tr '[:upper:]' '[:lower:]')"
if [[ "$F4_LC" != "no" ]]; then
  wc_val="$(count_words "$F4")"
  if [[ "$wc_val" -lt 4 ]]; then
    err "validation failed: line 4 is too short (${wc_val} words). Use 'no' or give specifics."
    err "  content: $F4"
    exit 3
  fi
fi

F5_LC="$(printf '%s' "$F5" | tr '[:upper:]' '[:lower:]')"
F5_WORDS="$(count_words "$F5")"
if [[ "$F5_LC" != "none, closed" && "$F5_WORDS" -lt 4 ]]; then
  err "validation failed: line 5 is too short (${F5_WORDS} words). Use 'none, closed' or give a concrete next step."
  err "  content: $F5"
  exit 3
fi

PLACEHOLDERS='(<[^>]+>|\bTODO\b|\bTBD\b|\.\.\.|\bfill in\b|\bfoo\b|\bbar\b)'
JARGON='(/Users/|/tmp/|gs://|file://|s3://|https?://|[A-Za-z0-9._-]+\.[A-Za-z0-9._-]+:[0-9]+|\bexit [0-9]+\b|\bstatus [0-9]+\b|\bstacktrace\b|\bstderr\b|\bstdout\b)'

for i in 1 2 3 4 5; do
  val_var="F${i}"
  val="${!val_var}"
  if printf '%s' "$val" | grep -E -i -q "$PLACEHOLDERS"; then
    err "validation failed: line ${i} contains a placeholder"
    err "  content: $val"
    exit 3
  fi
  if printf '%s' "$val" | grep -E -q "$JARGON"; then
    err "validation failed: line ${i} contains a path, URL, or execution detail"
    err "  content: $val"
    exit 3
  fi
done

TMPDIR_LOCAL="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_LOCAL"' EXIT

MATCH_JSON="$TMPDIR_LOCAL/match.json"

"$PYTHON_BIN" - "$HANDOFF_LOG" "$FROM" "$F3" "$HANDOFF_TIMESTAMP" "$MATCH_JSON" <<'PY'
import json
import re
import sys
from pathlib import Path

log_path = Path(sys.argv[1])
closer = sys.argv[2]
closes_text = sys.argv[3].strip()
explicit_ts = sys.argv[4].strip()
out_path = Path(sys.argv[5])

def normalize(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", text.lower()).strip()

def tokens(text: str):
    return [t for t in normalize(text).split() if len(t) >= 4]

def row_topic(row):
    parts = [
        row.get("did_or_tried", ""),
        row.get("next_step", ""),
        row.get("raw", ""),
        row.get("topic", ""),
        row.get("summary", ""),
    ]
    return " ".join(p for p in parts if p).strip()

rows = []
with log_path.open() as fh:
    for idx, line in enumerate(fh):
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as exc:
            print(f"invalid JSONL row {idx+1}: {exc}", file=sys.stderr)
            sys.exit(3)
        rows.append((idx, row))

open_rows = []
for idx, row in rows:
    if row.get("completed_at"):
        continue
    if row.get("to") != closer:
        continue
    open_rows.append((idx, row))

if not open_rows:
    print(f"no open handoff assigned to {closer}", file=sys.stderr)
    sys.exit(3)

matches = []
if explicit_ts:
    matches = [(idx, row) for idx, row in open_rows if row.get("timestamp") == explicit_ts]
else:
    closes_lc = closes_text.lower()
    closes_tokens = set(tokens(closes_text))
    for idx, row in open_rows:
        ts = row.get("timestamp", "")
        topic = row_topic(row)
        topic_lc = topic.lower()
        topic_tokens = set(tokens(topic))
        date_only = ts[:10]
        minute_precision = ts[:16]
        if ts and ts in closes_text:
            matches.append((idx, row))
            continue
        if date_only and date_only in closes_text:
            matches.append((idx, row))
            continue
        if minute_precision and minute_precision in closes_text:
            matches.append((idx, row))
            continue
        if closes_lc and closes_lc != "none":
            shared = closes_tokens & topic_tokens
            if len(shared) >= 3:
                matches.append((idx, row))
                continue
            if normalize(closes_text) and normalize(closes_text) in normalize(topic_lc):
                matches.append((idx, row))
                continue
    if not matches and len(open_rows) == 1:
        matches = open_rows[:]

if len(matches) != 1:
    if len(matches) == 0:
      print("no matching open handoff found in JSONL log", file=sys.stderr)
    else:
      print("multiple open handoffs match; pass --handoff-timestamp to disambiguate", file=sys.stderr)
    sys.exit(3)

idx, row = matches[0]
payload = {
    "index": idx,
    "row": row,
}
out_path.write_text(json.dumps(payload))
PY

MATCH_INDEX="$("$PYTHON_BIN" -c 'import json,sys; print(json.load(open(sys.argv[1]))["index"])' "$MATCH_JSON")"
ORIGIN_CHANNEL="$("$PYTHON_BIN" -c 'import json,sys; print(json.load(open(sys.argv[1]))["row"].get("origin_channel",""))' "$MATCH_JSON")"
ORIGIN_ACCOUNT="$("$PYTHON_BIN" -c 'import json,sys; print(json.load(open(sys.argv[1]))["row"].get("origin_account",""))' "$MATCH_JSON")"
ORIGIN_FROM="$("$PYTHON_BIN" -c 'import json,sys; print(json.load(open(sys.argv[1]))["row"].get("from",""))' "$MATCH_JSON")"
ORIGIN_TS="$("$PYTHON_BIN" -c 'import json,sys; print(json.load(open(sys.argv[1]))["row"].get("timestamp",""))' "$MATCH_JSON")"

CHANNEL_INFO_RAW="$("$PYTHON_BIN" - "$OPENCLAW_CONFIG" "$FROM" "$ORIGIN_FROM" "$ORIGIN_CHANNEL" "$ORIGIN_ACCOUNT" <<'PY'
import json
import sys
from pathlib import Path

cfg = json.loads(Path(sys.argv[1]).read_text())
closer = sys.argv[2]
origin_from = sys.argv[3]
origin_channel = sys.argv[4]
origin_account = sys.argv[5]

slack = cfg.get("channels", {}).get("slack", {})
accounts = slack.get("accounts", {})
global_channels = set((slack.get("channels") or {}).keys())

def account_channel(agent_id):
    if agent_id == "ranveer":
        if global_channels:
            return ("default", sorted(global_channels)[0])
        return ("default", "")
    acct = accounts.get(agent_id) or {}
    acct_channels = acct.get("channels") or {}
    if acct_channels:
        return (agent_id, sorted(acct_channels.keys())[0])
    return (agent_id, "")

closer_account, closer_channel = account_channel(closer)
if origin_channel:
    resolved_origin_channel = origin_channel
else:
    _, resolved_origin_channel = account_channel(origin_from)

if origin_account:
    resolved_origin_account = origin_account
elif resolved_origin_channel in global_channels:
    resolved_origin_account = "default"
else:
    resolved_origin_account = origin_from or "default"

print(closer_account)
print(closer_channel)
print(resolved_origin_account)
print(resolved_origin_channel)
PY
)"

CLOSER_ACCOUNT="$(printf '%s\n' "$CHANNEL_INFO_RAW" | sed -n '1p')"
CLOSER_CHANNEL="$(printf '%s\n' "$CHANNEL_INFO_RAW" | sed -n '2p')"
POST_ORIGIN_ACCOUNT="$(printf '%s\n' "$CHANNEL_INFO_RAW" | sed -n '3p')"
POST_ORIGIN_CHANNEL="$(printf '%s\n' "$CHANNEL_INFO_RAW" | sed -n '4p')"

[[ -z "$CLOSER_CHANNEL" ]] && { err "could not resolve closer home channel for $FROM"; exit 4; }
[[ -z "$POST_ORIGIN_CHANNEL" ]] && { err "could not resolve originating channel"; exit 4; }

SANITIZED_MSG="$TMPDIR_LOCAL/sanitized.txt"
node --input-type=module - "$VALIDATOR_LIB" "$OPENCLAW_CONFIG" "$MSG_FILE" "$POST_ORIGIN_CHANNEL" "$POST_ORIGIN_ACCOUNT" "$SANITIZED_MSG" <<'JS'
import fs from "node:fs";

const [, , validatorLib, configPath, messageFile, channelId, accountId, outPath] = process.argv;
const cfg = JSON.parse(fs.readFileSync(configPath, "utf8"));
const message = fs.readFileSync(messageFile, "utf8");
const pluginCfg =
  cfg?.plugins?.entries?.["outbound-slack-validator"]?.config ?? {};

const { rewriteOutbound } = await import(`file://${validatorLib}`);
const result = await rewriteOutbound(message, {
  mode: pluginCfg.mode ?? "autofix",
  maxInlineBytes: pluginCfg.maxInlineBytes ?? 30000,
  gcsTimeoutMs: pluginCfg.gcsTimeoutMs ?? 10000,
  channelId,
  accountId: accountId || null,
  channelAllowlist: pluginCfg.channelAllowlist ?? {},
  metadata: { handoff: true },
});

if (result?.cancel) {
  console.error("validator cancelled outbound message");
  process.exit(4);
}

fs.writeFileSync(outPath, result?.content ?? message);
JS

COMPLETION_RAW="$(cat "$SANITIZED_MSG")"
COMPLETION_SUMMARY="$F1"
COMPLETED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

"$PYTHON_BIN" - "$HANDOFF_LOG" "$MATCH_INDEX" "$COMPLETED_AT" "$COMPLETION_SUMMARY" "$COMPLETION_RAW" "$FROM" <<'PY'
import json
import os
import sys
import tempfile
from pathlib import Path

log_path = Path(sys.argv[1])
target_index = int(sys.argv[2])
completed_at = sys.argv[3]
completion_summary = sys.argv[4]
completion_raw = sys.argv[5]
completed_by = sys.argv[6]

lines = log_path.read_text().splitlines()
rows = [json.loads(line) for line in lines if line.strip()]
row = rows[target_index]
if row.get("completed_at"):
    print("handoff already closed", file=sys.stderr)
    sys.exit(3)
row["completed_at"] = completed_at
row["completion_summary"] = completion_summary
row["completion_raw"] = completion_raw
row["completed_by"] = completed_by

fd, tmp = tempfile.mkstemp(prefix="handoff-log-", suffix=".jsonl", dir=str(log_path.parent))
os.close(fd)
tmp_path = Path(tmp)
tmp_path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows))
tmp_path.replace(log_path)
PY

send_message() {
  local account="$1"
  local channel="$2"
  local text_file="$3"
  if [[ "$DRY_RUN" == "true" ]]; then
    printf 'handoff-complete: dry-run post account=%s channel=%s\n' "$account" "$channel" >&2
    cat "$text_file"
    printf '\n---\n'
    return 0
  fi

  if [[ -n "$account" ]]; then
    "$OPENCLAW_BIN" message send --channel slack --account "$account" --target "$channel" --message "$(cat "$text_file")" >/dev/null
  else
    "$OPENCLAW_BIN" message send --channel slack --target "$channel" --message "$(cat "$text_file")" >/dev/null
  fi
}

send_message "$POST_ORIGIN_ACCOUNT" "$POST_ORIGIN_CHANNEL" "$SANITIZED_MSG"
if [[ "$CLOSER_CHANNEL" != "$POST_ORIGIN_CHANNEL" || "$CLOSER_ACCOUNT" != "$POST_ORIGIN_ACCOUNT" ]]; then
  send_message "$CLOSER_ACCOUNT" "$CLOSER_CHANNEL" "$SANITIZED_MSG"
fi

printf 'handoff-complete: validated, closed %s, posted to %s and %s\n' \
  "$ORIGIN_TS" "$POST_ORIGIN_CHANNEL" "$CLOSER_CHANNEL" >&2

#!/usr/bin/env bash
set -euo pipefail

say() {
  printf '[avalai-codex-e2e] %s\n' "$*"
}

fail() {
  printf '[avalai-codex-e2e] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

if [[ -z "${AVALAI_API_KEY:-}" || "${AVALAI_API_KEY}" == "null" ]]; then
  fail "set AVALAI_API_KEY to a real AvalAI key before running this script"
fi

require_cmd curl
require_cmd cargo
require_cmd grep

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${REPO_ROOT:-}" ]]; then
  repo_root="$REPO_ROOT"
elif repo_root="$(git -C "$script_dir/../.." rev-parse --show-toplevel 2>/dev/null)"; then
  :
else
  repo_root="$(cd "$script_dir/../.." && pwd)"
fi
codex_rs_dir="$repo_root/codex-rs"

[[ -d "$codex_rs_dir" ]] || fail "codex-rs not found at $codex_rs_dir"

model="${AVALAI_MODEL:-deepseek-v4-pro}"
base_url="${AVALAI_BASE_URL:-https://api.avalai.ir/v1}"
codex_home="${CODEX_HOME:-/tmp/codex-avalai-home-e2e}"
curl_timeout="${AVALAI_CURL_TIMEOUT:-60}"
tmp_dir="${TMPDIR:-/tmp}/avalai-codex-e2e.$$"

mkdir -p "$codex_home" "$tmp_dir"

say "repo root: $repo_root"
say "model: $model"
say "base URL: $base_url"
say "temporary output: $tmp_dir"

cat >"$tmp_dir/text.json" <<JSON
{"model":"$model","input":"Reply with OK only."}
JSON

say "checking non-streaming /v1/responses"
status="$(
  curl -sS \
    -o "$tmp_dir/text-response.json" \
    -w '%{http_code}' \
    "$base_url/responses" \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer ${AVALAI_API_KEY}" \
    --data-binary @"$tmp_dir/text.json"
)"

[[ "$status" == "200" ]] || fail "non-streaming response returned HTTP $status; see $tmp_dir/text-response.json"
grep -Eq '"status"[[:space:]]*:[[:space:]]*"completed"' "$tmp_dir/text-response.json" || fail "non-streaming response did not complete"
grep -Eq '"text"[[:space:]]*:[[:space:]]*"OK"' "$tmp_dir/text-response.json" || fail "non-streaming response did not contain OK"

cat >"$tmp_dir/text-stream.json" <<JSON
{"model":"$model","input":"Reply with OK only.","stream":true}
JSON

say "checking streaming /v1/responses"
curl -sS -N \
  --max-time "$curl_timeout" \
  "$base_url/responses" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${AVALAI_API_KEY}" \
  --data-binary @"$tmp_dir/text-stream.json" \
  >"$tmp_dir/text-stream.sse"

grep -q 'response.completed' "$tmp_dir/text-stream.sse" || fail "streaming response did not complete"
grep -Eq '"(delta|text)":"OK"' "$tmp_dir/text-stream.sse" || fail "streaming response did not contain OK"

cat >"$tmp_dir/tool-stream.json" <<JSON
{
  "model": "$model",
  "input": "Call the exec_command tool with cmd set to ls.",
  "stream": true,
  "tools": [
    {
      "type": "function",
      "name": "exec_command",
      "description": "Run a shell command.",
      "parameters": {
        "type": "object",
        "properties": {
          "cmd": { "type": "string" }
        },
        "required": ["cmd"],
        "additionalProperties": false
      },
      "strict": false
    }
  ]
}
JSON

say "checking streaming function-call support"
curl -sS -N \
  --max-time "$curl_timeout" \
  "$base_url/responses" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${AVALAI_API_KEY}" \
  --data-binary @"$tmp_dir/tool-stream.json" \
  >"$tmp_dir/tool-stream.sse"

grep -q 'response.function_call_arguments.done' "$tmp_dir/tool-stream.sse" || fail "tool probe did not emit completed function arguments"
grep -q 'exec_command' "$tmp_dir/tool-stream.sse" || fail "tool probe did not call exec_command"

say "checking reduced-context codex exec tool run"
(
  cd "$codex_rs_dir"
  CODEX_HOME="$codex_home" \
  AVALAI_API_KEY="$AVALAI_API_KEY" \
  cargo run -p codex-cli --bin codex -- exec \
    --ignore-user-config \
    --avalai \
    --cd "$repo_root" \
    --sandbox workspace-write \
    --ephemeral \
    --json \
    --disable plugins \
    --disable remote_plugin \
    --disable apps \
    --disable image_generation \
    --disable tool_suggest \
    --disable multi_agent \
    --disable guardian_approval \
    --disable goals \
    -c skills.include_instructions=false \
    -c skills.bundled.enabled=false \
    "Run exactly: ls"
) >"$tmp_dir/codex-reduced.jsonl" 2>&1

grep -q '"type":"command_execution"' "$tmp_dir/codex-reduced.jsonl" || fail "codex run did not execute a command"
grep -q '"type":"turn.completed"' "$tmp_dir/codex-reduced.jsonl" || fail "codex run did not complete"
grep -q 'AGENTS.md' "$tmp_dir/codex-reduced.jsonl" || fail "codex ls output did not include AGENTS.md"

if [[ "${RUN_FULL_AVALAI_E2E:-0}" == "1" ]]; then
  say "checking full default codex exec path; failures here are diagnostic"
  set +e
  (
    cd "$codex_rs_dir"
    CODEX_HOME="$codex_home" \
    AVALAI_API_KEY="$AVALAI_API_KEY" \
    cargo run -p codex-cli --bin codex -- exec \
      --ignore-user-config \
      --avalai \
      --cd "$repo_root" \
      --sandbox workspace-write \
      --ephemeral \
      --json \
      "Run exactly: ls"
  ) >"$tmp_dir/codex-full.jsonl" 2>&1
  full_status=$?
  set -e
  if [[ "$full_status" -eq 0 ]]; then
    say "full default path completed"
  else
    say "full default path failed with status $full_status; see $tmp_dir/codex-full.jsonl"
  fi
fi

say "PASS"
say "artifacts kept in $tmp_dir"

#!/usr/bin/env bash
set -Eeuo pipefail

change_type="${1:-feature}"
description="${2:-}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(git -C "${script_dir}/../.." rev-parse --show-toplevel)"

cd "${repo_root}"

slug="$(
  printf '%s' "${description}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g' \
    | cut -c1-80
)"
[[ -n "${slug}" ]] || slug="codex-toolchain-change"

branch="${change_type}/${slug}"
intent_dir=".agent/change-intents"
intent_path="${intent_dir}/${branch//\//-}.md"

mkdir -p "${intent_dir}"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git show-ref --verify --quiet "refs/heads/${branch}"; then
    git switch "${branch}" >/dev/null
  else
    git switch -c "${branch}" >/dev/null
  fi
fi

cat >"${intent_path}" <<INTENT
# ${change_type}: ${description}

## Objective

${description}

## Scope

- Preserve upstream Codex compatibility unless the task explicitly changes it.
- Keep the Divband overlay, migration runner, and generated output provenance in sync.
- Do not commit credentials, profile homes, build caches, generated binaries, or raw task logs.

## Validation

- \`scripts/local/check-change.sh\`
- For overlay or Rust changes, select a focused command from \`.agent/test-map.psv\`.
INTENT

printf '{"branch":"%s","intent_path":"%s"}\n' "${branch}" "${intent_path}"

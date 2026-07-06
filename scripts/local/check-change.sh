#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(git -C "${script_dir}/../.." rev-parse --show-toplevel)"
package_dir="${repo_root}/agent-coordinator/divband-codex"
output_dir="${repo_root}/agent-coordinator/divband-codex-output"

required_docs=(
  README.md
  FEATURES.md
  IMPLEMENTATION.md
  REBASE_PLAYBOOK.md
  TESTING.md
  TOOLCHAIN.md
  diffstat.txt
  file-inventory.txt
)

for doc in "${required_docs[@]}"; do
  [[ -f "${package_dir}/${doc}" ]] || {
    echo "missing migration document: ${package_dir}/${doc}" >&2
    exit 1
  }
done

[[ -f "${package_dir}/divband-codex.patch" ]] || {
  echo "missing overlay patch: ${package_dir}/divband-codex.patch" >&2
  exit 1
}

patch_count="$(
  find "${package_dir}/patches" -maxdepth 1 -type f -name '*.patch' | wc -l
)"
if ((patch_count < 1)); then
  echo "missing per-commit overlay patches in ${package_dir}/patches" >&2
  exit 1
fi

[[ -d "${package_dir}/codex/.git" ]] || {
  echo "missing vanilla source clone: ${package_dir}/codex/.git" >&2
  exit 1
}

[[ -d "${output_dir}/.git" ]] || {
  echo "missing generated output repo: ${output_dir}/.git" >&2
  exit 1
}

python3 -m py_compile \
  "${package_dir}/run.py" \
  "${package_dir}/toolchain/orchestrator.py"

python3 "${package_dir}/run.py" \
  --dry-run \
  --agents off \
  --skip-build \
  --test-profile none \
  --skip-copy-artifacts >/dev/null

echo "divband-codex lightweight validation passed"

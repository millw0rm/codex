#!/usr/bin/env bash
set -Eeuo pipefail

selector="${1:-default}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(git -C "${script_dir}/../.." rev-parse --show-toplevel)"

awk -F'|' -v selector="${selector}" '
  NR == 1 { next }
  $2 == selector || $2 == "default" { print }
' "${repo_root}/.agent/test-map.psv"

#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(git -C "${script_dir}/../.." rev-parse --show-toplevel)"

git -C "${repo_root}" status --short
git -C "${repo_root}" diff --stat

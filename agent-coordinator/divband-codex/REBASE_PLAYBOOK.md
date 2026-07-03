# Rebase Playbook

Use this when OpenAI publishes a new production Codex version and the Divband
changes need to be carried forward.

## 1. Prepare A New Branch

```shell
git fetch origin main
git switch -c divband-codex-YYYYMMDD origin/main
```

If working from a release tag instead of `origin/main`, start from that tag.

## 2. Apply The Overlay

Preferred path, preserving the original logical commits:

```shell
git am /path/to/divband-codex/patches/*.patch
```

Conflict-friendly fallback:

```shell
git apply --3way /path/to/divband-codex/divband-codex.patch
git add -A
git commit -m "feat: apply divband codex overlay"
```

If `git am` stops on a conflict:

```shell
git status
# resolve files
git add <resolved-files>
git am --continue
```

Use `git am --abort` only when you want to restart the entire application.

## 3. Expected Conflict Areas

Resolve in this order:

1. CLI argument surfaces:
   `codex-rs/cli/src/main.rs`, `codex-rs/tui/src/cli.rs`,
   `codex-rs/exec/src/cli.rs`, `codex-rs/utils/cli/src/shared_options.rs`.
2. Config/session construction:
   `codex-rs/core/src/config/mod.rs`,
   `codex-rs/core/src/session/session.rs`,
   `codex-rs/core/src/state/service.rs`.
3. Sampling and usage-limit handling:
   `codex-rs/core/src/session/turn.rs`.
4. App-server protocol macros and generated schema files:
   `codex-rs/app-server-protocol/src/protocol/common.rs`,
   `codex-rs/app-server-protocol/src/protocol/v2/thread.rs`,
   `codex-rs/app-server-protocol/schema/`.
5. TUI slash command dispatch:
   `codex-rs/tui/src/slash_command.rs`,
   `codex-rs/tui/src/chatwidget/slash_dispatch.rs`.
6. MCP tool registration:
   `codex-rs/mcp-server/src/message_processor.rs`,
   `codex-rs/mcp-server/src/lib.rs`.
7. Tests and snapshots.

## 4. Regenerate Generated Files

If app-server protocol types or methods conflict or change, regenerate schemas:

```shell
cd codex-rs
just write-app-server-schema
```

If Rust dependencies drift or `Cargo.toml` / `Cargo.lock` changes are adjusted,
refresh Bazel lock state:

```shell
cd codex-rs
just bazel-lock-update
```

## 5. Format And Test

Use low-resource Cargo jobs on smaller machines:

```shell
cd codex-rs
CARGO_BUILD_JOBS=1 just fmt
CARGO_BUILD_JOBS=1 just test -p codex-cli best_profile
CARGO_BUILD_JOBS=1 just test -p codex-cli resume_best
CARGO_BUILD_JOBS=1 just test -p codex-app-server thread_profile_refresh
CARGO_BUILD_JOBS=1 just test -p codex-core usage_limit_switches_profile_and_retries_turn
CARGO_BUILD_JOBS=1 just test -p codex-mcp-server cursor_session
CARGO_BUILD_JOBS=1 just fix -p codex-core
```

If `usage_limit_switches_profile_and_retries_turn` skips because the Codex
sandbox disables networking, rerun that one test outside the sandbox. It uses a
mock server, but the test helper intentionally skips under the network-disabled
sandbox environment.

Do not run the full workspace suite on memory-constrained machines unless it is
really needed.

## 6. Manual Smoke Checks

After automated checks pass, run a few local commands:

```shell
codex profiles list
codex profiles limits --refresh
codex profiles best --refresh
codex --best
codex exec --avalai "say hello"
```

Inside TUI:

```text
/refresh-profile
```

For Cursor MCP, only run this when `cursor-agent` and a mounted Cursor home are
available:

```text
tools/list should include cursor-session
tools/call cursor-session with prompt should return structured output
```

## 7. Refresh This Migration Package

After the new overlay branch is correct, regenerate the artifacts:

```shell
BASE=$(git merge-base origin/main HEAD)
git diff --binary "$BASE"..HEAD --output=agent-coordinator/divband-codex/divband-codex.patch
git diff --stat "$BASE"..HEAD --output=agent-coordinator/divband-codex/diffstat.txt
git diff --name-status "$BASE"..HEAD --output=agent-coordinator/divband-codex/file-inventory.txt
rm -rf agent-coordinator/divband-codex/patches
mkdir -p agent-coordinator/divband-codex/patches
git format-patch --output-directory=agent-coordinator/divband-codex/patches "$BASE"..HEAD
```

Then update the snapshot metadata in `README.md`.


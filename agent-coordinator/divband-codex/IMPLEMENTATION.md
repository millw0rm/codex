# Implementation Map

This file maps the overlay by crate and code path so future rebases can resolve
conflicts by ownership area.

## CLI Profile Management

Primary files:

- `codex-rs/cli/src/profile_manager_cmd.rs`
- `codex-rs/cli/src/profile_manager_cmd/auth.rs`
- `codex-rs/cli/src/profile_manager_cmd/fs_utils.rs`
- `codex-rs/cli/src/profile_manager_cmd/limits.rs`
- `codex-rs/cli/src/profile_manager_cmd/project.rs`
- `codex-rs/cli/src/profile_manager_cmd/root.rs`
- `codex-rs/cli/src/bin/codex-profiles.rs`
- `codex-rs/cli/src/main.rs`

Responsibilities:

- Define the `codex profiles` command tree.
- Provide the standalone `codex-profiles` binary.
- Manage profile homes and auth import/login.
- Fetch and cache profile usage limits.
- Rank usable profiles.
- Launch Codex with the chosen profile.
- Prepare `BestProfileLaunch` for `codex --best`.

Dependency impact:

- `codex-rs/cli/Cargo.toml` adds the `codex-profiles` binary and `reqwest`
  with blocking/json/rustls features.
- `codex-rs/Cargo.lock` gains the CLI dependency edge.

## Shared CLI Helpers

Primary files:

- `codex-rs/utils/cli/src/shared_options.rs`
- `codex-rs/utils/cli/src/model_provider_shortcuts.rs`
- `codex-rs/utils/cli/src/project_home.rs`
- `codex-rs/utils/cli/src/lib.rs`

Responsibilities:

- Define shared `--avalai`, `--project`, and `--project-dir` options.
- Provide AvalAI model-provider override generation.
- Prepare stable per-project `CODEX_HOME` directories.

## Interactive And Exec Launch

Primary files:

- `codex-rs/cli/src/main.rs`
- `codex-rs/exec/src/cli.rs`
- `codex-rs/exec/src/lib.rs`
- `codex-rs/tui/src/cli.rs`
- `codex-rs/tui/src/lib.rs`

Responsibilities:

- Accept `--best`, `--avalai`, and project flags in the intended launch modes.
- Reject remote mode for local-only profile operations.
- Resolve per-project homes before config loading.
- Load config from the base home when a project home is active.
- Pass runtime `ProfileAuthFailoverConfig` into core.

## Core Runtime Failover

Primary files:

- `codex-rs/core/src/config/mod.rs`
- `codex-rs/core/src/session/profile_auth_failover.rs`
- `codex-rs/core/src/session/managed_profiles.rs`
- `codex-rs/core/src/session/session.rs`
- `codex-rs/core/src/session/turn.rs`
- `codex-rs/core/src/session/handlers.rs`
- `codex-rs/core/src/state/service.rs`
- `codex-rs/protocol/src/protocol.rs`

Responsibilities:

- Carry runtime-only profile failover settings through `ConfigOverrides`.
- Store failover service state in `SessionServices`.
- Switch auth on usage-limit errors and retry the turn.
- Write limited cache entries when available.
- Refresh managed profile limits.
- Handle `Op::RefreshProfileAuth` without starting a turn.

Important behavior:

- `ProfileAuthFailoverConfig` is intentionally not a persistent config-toml
  type. It is launch-time state.
- `Op::RefreshProfileAuth` is bounded: it emits a warning event and does not
  inject content into model-visible conversation context.

## App-Server And TUI Refresh Flow

Primary files:

- `codex-rs/app-server-protocol/src/protocol/common.rs`
- `codex-rs/app-server-protocol/src/protocol/v2/thread.rs`
- `codex-rs/app-server/src/message_processor.rs`
- `codex-rs/app-server/src/request_processors/thread_processor.rs`
- `codex-rs/tui/src/app_server_session.rs`
- `codex-rs/tui/src/app/thread_routing.rs`
- `codex-rs/tui/src/app_command.rs`
- `codex-rs/tui/src/slash_command.rs`
- `codex-rs/tui/src/chatwidget/slash_dispatch.rs`

Responsibilities:

- Add `thread/profile/refresh`.
- Route the request to `Op::RefreshProfileAuth`.
- Expose `/refresh-profile` and `/refresh-profiles` in the TUI.
- Ensure the command path does not start a turn.

Generated files:

- App-server JSON schema under `codex-rs/app-server-protocol/schema/json/`.
- App-server TypeScript schema under
  `codex-rs/app-server-protocol/schema/typescript/`.

## Cursor Session MCP Tool

Primary files:

- `codex-rs/mcp-server/src/cursor_session.rs`
- `codex-rs/mcp-server/src/cursor_session_tests.rs`
- `codex-rs/mcp-server/src/message_processor.rs`
- `codex-rs/mcp-server/src/lib.rs`
- `codex-rs/mcp-server/src/codex_tool_config.rs`

Responsibilities:

- Define the `cursor-session` MCP tool schema.
- Validate mounted Cursor auth state.
- Run `cursor-agent` with bounded timeout and output capture.
- Return structured tool output.
- Register the tool in `tools/list` and route `tools/call`.

## Tests

Focused tests were added in:

- `codex-rs/cli/src/profile_manager_cmd_tests.rs`
- `codex-rs/cli/src/profile_pool_cmd_tests.rs`
- `codex-rs/core/src/session/profile_auth_failover_tests.rs`
- `codex-rs/core/src/session/managed_profiles_tests.rs`
- `codex-rs/core/tests/suite/profile_auth_failover.rs`
- `codex-rs/app-server/tests/suite/v2/thread_profile_refresh.rs`
- `codex-rs/tui/src/chatwidget/tests/slash_commands.rs`
- `codex-rs/mcp-server/src/cursor_session_tests.rs`
- `codex-rs/mcp-server/tests/suite/cursor_session_tool.rs`
- `codex-rs/exec/src/cli_tests.rs`

## Generated And Operational Files

- `.github/workflows/fork-release.yml`: fork release workflow.
- `agent-coordinator/`: project/operator notes and e2e script.
- `agent-coordinator/divband-codex/`: this migration package.


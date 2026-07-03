# Feature List

This overlay adds a Divband-flavored account/profile workflow, provider
shortcuts, per-project homes, runtime profile failover, and a Cursor-backed MCP
subagent tool.

## 1. Managed Codex Profiles

Adds a local profile manager for self-contained Codex account homes.

Entry points:

- `codex-profiles`
- `codex profiles`

Main capabilities:

- Initialize the managed profile root.
- Add a profile home and optionally run `codex login`.
- Import an `auth.json` from another `CODEX_HOME` or file.
- Run `codex login` inside a selected profile.
- Select and inspect the current/default profile.
- List, remove, and print profile homes.
- Print shell exports for using a profile home.
- Resolve stable project homes for directories.
- Run Codex with a selected profile.
- Refresh, cache, rank, and display usage-limit status.
- Select the best currently usable existing profile.

The manager deliberately selects from existing profiles. It does not create or
log into a new account automatically when quota is exhausted.

## 2. `--best` Profile Selection

Adds `--best` to interactive Codex launch flows so Codex can start with the
least-used managed profile.

Supported launch paths:

- `codex --best`
- `codex resume --best ...`
- `codex fork --best ...`

Behavior:

- Refreshes managed profile usage before launch.
- Ranks profiles by highest pressure across relevant usage windows.
- Picks the best usable existing candidate.
- Copies that profile's `auth.json` into a stable project home.
- Passes runtime failover candidates into core through `ConfigOverrides`.
- Rejects remote mode for `--best`, because auth swapping is local
  `CODEX_HOME` state and cannot be safely handled by a remote server.

## 3. Stable Project Homes

Adds shared project-home helpers in `codex_utils_cli`.

Behavior:

- Creates a stable per-project `CODEX_HOME`.
- Validates project ids.
- Resolves the Git root when available.
- Writes marker files such as `.codex-project-root`, `.codex-project-id`, and
  `.codex-project-source-home`.
- Copies `auth.json` from the source home when needed.
- Preserves private file and directory permissions on Unix.

This lets a single project keep a stable session/config/auth location while
still allowing `--best` to swap credentials inside that home.

## 4. Runtime Auth Failover

Adds core runtime failover for usage-limit errors.

Behavior:

- On `UsageLimitReached`, core marks the active profile as limited.
- If rate-limit details are available, it writes a limited usage cache entry for
  the active profile.
- It copies the next candidate's `auth.json` into the active project home.
- It reloads the shared `AuthManager`.
- It resets the model-client session so the retry does not reuse stale auth.
- It emits a warning and retries the current turn.
- If no next candidate exists, the original usage-limit error is returned.

This is intentionally runtime-only configuration. It is populated by launch
code and is not a persistent `config.toml` setting.

## 5. Manual Profile Refresh And Switch

Adds a manual profile-refresh path that does not start a new user turn.

Surfaces:

- TUI slash command: `/refresh-profile`
- TUI canonical command string: `/refresh-profiles`
- Core op: `Op::RefreshProfileAuth`
- App-server v2 method: `thread/profile/refresh`

Behavior:

- Refreshes managed profile usage-limit cache.
- Attempts to switch to the next configured failover profile.
- Emits a warning notification summarizing refresh/switch status.
- Does not mutate conversation history or start a turn.

## 6. App-Server API Surface

Adds v2 JSON-RPC API support for profile refresh:

- `ThreadProfileRefreshParams`
- `ThreadProfileRefreshResponse`
- `ClientRequest::ThreadProfileRefresh`
- `thread/profile/refresh`

Generated JSON schema and TypeScript fixtures are included so downstream
clients can call the method consistently.

## 7. AvalAI Provider Shortcut

Adds an AvalAI shortcut in shared CLI options.

Behavior:

- `--avalai` prepends config overrides for provider id `avalai`.
- Default model: `deepseek-v4-pro`.
- Base URL: `https://api.avalai.ir/v1`.
- API key env var: `AVALAI_API_KEY`.
- Wire API: `responses`.
- Conflicts with `--oss` and local-provider options.
- Propagates through interactive and exec resume paths where global CLI flags
  are accepted.

## 8. Experimental Profile Pool Check

Adds `codex pool` as an experimental local validation helper.

Capabilities:

- Reads a pool file, defaulting to `$CODEX_HOME/pool.toml`.
- Supports `status` and `test` subcommands.
- Validates profile ids, config profiles, config loadability, and auth health.
- Can output JSON for automation.

This is separate from managed profiles. It is useful for inspecting a portable
set of profile homes before wiring them into higher-level automation.

## 9. Cursor Session MCP Tool

Adds an MCP tool named `cursor-session`.

Purpose:

- Ask Cursor Agent to perform bounded analysis using a mounted Cursor login
  profile.
- Keep Codex responsible for planning, code edits, and final coordination.
- Use Cursor as a sidecar/subagent for research when the environment supports it.

Inputs:

- `prompt`
- `cwd`
- `command`
- `cursor-home`
- `mode`
- `model`
- `timeout-seconds`
- `output-max-bytes`

Defaults:

- Command: `CURSOR_SESSION_AGENT_COMMAND` or `cursor-agent`.
- Cursor home: `CURSOR_SESSION_HOME` or `/cursor-home`.
- Mode: `CURSOR_SESSION_MODE` or `ask`.
- Model: `CURSOR_SESSION_MODEL` or `auto`.
- Timeout: 900 seconds.
- Output cap: 16000 bytes.

Output is structured with stdout, stderr, exit code, timeout state, and
truncation flags.

## 10. Fork Release Workflow

Adds a GitHub Actions workflow for fork-oriented release builds.

This is intended for maintaining a Divband fork without depending on upstream
OpenAI release automation being directly writable from the fork.

## 11. Agent Coordinator Notes

Adds `agent-coordinator/` notes and an AvalAI/Codex e2e script. These files are
operator documentation for coordinating this fork and preserving the rationale
behind the custom workflow.


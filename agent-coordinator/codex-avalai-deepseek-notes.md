# Codex AvalAI and DeepSeek Notes

Last updated: 2026-07-03

## Purpose

This note captures the current understanding of the AvalAI shortcut work in this
Codex checkout. It is intended for an agent coordinator that needs to know what
was changed, how the CLI path is wired, what assumptions remain, and where to
look next.

## Current Behavior

The local working tree implements a `--avalai` CLI shortcut.

Supported command shapes:

```bash
codex --avalai
codex exec --avalai
codex resume --avalai
codex exec resume --avalai
```

The shortcut injects config overrides before normal Codex config loading:

```toml
model_provider = "avalai"
model = "deepseek-v4-pro"

[model_providers.avalai]
name = "AvalAI"
base_url = "https://api.avalai.ir/v1"
env_key = "AVALAI_API_KEY"
env_key_instructions = "Set the AVALAI_API_KEY environment variable to your AvalAI API key."
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
```

Explicit user model overrides still win. For example, `codex --avalai -m
some-other-model` should use `some-other-model`, because `-m/--model` is applied
through `ConfigOverrides::model` after the CLI config override layer.

## Important Files

- `codex-rs/utils/cli/src/shared_options.rs`
  - Defines the shared `--avalai` flag.
  - Keeps it mutually exclusive with `--oss` and `--local-provider`.
  - Handles inheritance/merge behavior for root and subcommand flags.

- `codex-rs/utils/cli/src/model_provider_shortcuts.rs`
  - Defines the AvalAI provider shortcut constants.
  - Adds the default model `deepseek-v4-pro`.
  - Prepends shortcut overrides so later user overrides keep precedence.

- `codex-rs/tui/src/lib.rs`
  - Applies AvalAI config overrides for interactive TUI launches.

- `codex-rs/exec/src/lib.rs`
  - Applies AvalAI config overrides for non-interactive `codex exec`.

- `codex-rs/tui/src/session_archive_commands.rs`
  - Applies AvalAI config overrides for archive/delete/unarchive flows that
    start an app-server session.

- `codex-rs/cli/src/main.rs`
  - Applies AvalAI overrides for debug prompt input.
  - Tests root CLI parsing, conflict behavior, resume merge behavior, and
    `codex exec resume --avalai`.

- `codex-rs/exec/src/cli.rs`
  - Marks `--oss`, `--avalai`, and `--local-provider` as global for exec
    subcommands. This is required because `--avalai` conflicts with the other
    two flags, and Clap requires conflict partners to exist in the subcommand
    parser when a global flag is accepted after the subcommand.

- `codex-rs/exec/src/cli_tests.rs`
  - Contains a socket-free parser test for `codex-exec resume --avalai`.

## Adapter Understanding

No new model adapter should be required if AvalAI is compatible with OpenAI's
Responses API at:

```text
POST https://api.avalai.ir/v1/responses
```

with payloads that include:

```json
{
  "model": "deepseek-v4-pro"
}
```

Codex currently treats AvalAI as an OpenAI-compatible Responses provider. That
means the existing Responses client path handles requests, streaming, and tool
calls.

An adapter or compatibility layer would be needed if AvalAI only supports
`/v1/chat/completions`, or if it accepts `/v1/responses` but diverges on tool
call events, streaming event shape, response item schema, auth headers, or model
catalog behavior.

## Model Slug Status

The configured default model slug is:

```text
deepseek-v4-pro
```

This slug was verified against AvalAI with a real key through direct
non-streaming and streaming `/v1/responses` probes, plus a reduced-context
`codex exec --avalai` tool run. Codex still reports a local metadata warning
because `deepseek-v4-pro` is not in the built-in model metadata table; that is a
local metadata/catalog issue, not proof that the AvalAI slug is invalid.

## Runtime Requirements

Set the AvalAI API key in the environment:

```bash
export AVALAI_API_KEY="..."
```

Then run a smoke test:

```bash
codex --avalai "Say hello and then stop."
```

Useful failure interpretation:

- `model not found`: update the default model slug or pass `-m`.
- `404 /v1/responses`: AvalAI may not expose the Responses endpoint; adapter or
  provider support work is needed.
- schema/tool/streaming errors: AvalAI may be only partially Responses-compatible;
  inspect the raw response and add compatibility handling if needed.
- auth errors: verify `AVALAI_API_KEY`, bearer header expectations, and account
  access for the selected model.

## Coordinator Flow for New Codex via AvalAI

The coordinator should treat AvalAI-backed Codex as a selectable execution
profile, not as a replacement for every Codex run. The current endpoint works,
but the full default Codex request envelope can exceed AvalAI's peak-load usage
limits. Use a staged flow.

### Profiles

`avalai-direct`

- Purpose: verify the API key, model slug, Responses endpoint, streaming, and
  basic function-call event shape without Codex runtime complexity.
- Surface: direct `POST /v1/responses` probes.
- Blocking for E2E: yes.

`avalai-codex-reduced`

- Purpose: run real `codex exec --avalai` with shell tools while keeping context
  and tool exposure small enough for AvalAI.
- Surface: `codex exec --ignore-user-config --avalai --ephemeral`.
- Default for automation and E2E: yes.
- Required reductions:
  - disable plugins,
  - disable remote plugin catalog,
  - disable apps,
  - disable image generation,
  - disable tool suggestions,
  - disable multi-agent/collab tools,
  - disable guardian approval,
  - disable goals,
  - disable automatic skill instructions and bundled skill injection.

`avalai-codex-full`

- Purpose: diagnostic compatibility check for normal Codex behavior.
- Surface: `codex exec --avalai` with default feature exposure.
- Blocking for E2E: no until AvalAI capacity or request-size behavior is known
  to support the full envelope reliably.

### E2E Gates

The minimum coordinator E2E path should run these gates in order:

1. `preflight`: `AVALAI_API_KEY` is present and is not the placeholder `null`.
2. `responses-text`: non-streaming `/v1/responses` returns HTTP 200 and model
   output `OK`.
3. `responses-stream`: streaming `/v1/responses` emits `response.completed`.
4. `responses-tool`: streaming `/v1/responses` with one tiny function tool emits
   completed tool-call arguments.
5. `codex-reduced`: reduced-context `codex exec --avalai` runs `ls` through the
   shell tool and reaches `turn.completed`.
6. `codex-full`: optional diagnostic run. Record failures, but do not fail the
   coordinator E2E solely on AvalAI peak-load / maximum-usage-size responses.

The runnable script for this path is:

```bash
AVALAI_API_KEY="..." agent-coordinator/e2e/avalai-codex-e2e.sh
```

Optional full-envelope diagnostic:

```bash
RUN_FULL_AVALAI_E2E=1 AVALAI_API_KEY="..." \
  agent-coordinator/e2e/avalai-codex-e2e.sh
```

The script keeps artifacts under `/tmp/avalai-codex-e2e.<pid>` and does not
write the API key to disk.

### Runtime Command Template

Use this command shape when the coordinator wants a dependable AvalAI-backed
Codex execution:

```bash
CODEX_HOME=/tmp/codex-avalai-home-e2e \
AVALAI_API_KEY="$AVALAI_API_KEY" \
cargo run -p codex-cli --bin codex -- exec \
  --ignore-user-config \
  --avalai \
  --cd "$REPO_ROOT" \
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
  "$PROMPT"
```

### Context and Memory Rules

Reduced-context AvalAI runs should be ephemeral by default. That keeps E2E runs
from generating durable memory and avoids mixing benchmark/tool output into the
user's long-lived context.

If a future coordinator flow enables plugins, apps, or MCP tools with AvalAI:

- apply the memory-pollution rules from this note,
- keep plugin/app/tool context bounded,
- prefer explicit selected capabilities over broad discovery,
- preserve `-c` override precedence so users can still change the model or
  provider details.

### Promotion Criteria

Promote `avalai-codex-full` from diagnostic to blocking only after:

- the full default Codex request completes under normal load,
- the model can execute at least one shell command through Codex,
- a deeper repo-inspection task completes with multiple tool calls,
- peak-load / maximum-usage-size failures are either rare or handled by a
  smaller default tool/context profile.

## Memory and Context Coordination

Codex maintains model-visible context as an incremental history of response
items. Coordinators should treat this as a cache-sensitive contract, not a loose
prompt string.

Core review rules from `AGENTS.md`:

- Do not rewrite history. Build context incrementally.
- Avoid frequent model-visible context churn that causes cache misses.
- Do not inject unbounded context. Every injected item needs a bounded size and
  a hard cap.
- Do not inject individual items larger than 10K tokens.
- Flag any new individual item that can exceed 1K tokens as P0 for manual
  review.
- All injected fragments should be concrete structs in `codex-rs/core/src/context`
  and implement `ContextualUserFragment`.

Important context files:

- `codex-rs/context-fragments/src/fragment.rs`
  - Defines `ContextualUserFragment`.
  - Fragments render into `ResponseItem::Message` with a role, body, and optional
    start/end markers.
  - Markers let history filtering recognize injected context later.

- `codex-rs/context-fragments/src/additional_context.rs`
  - Shows a bounded external context pattern.
  - Additional context values are truncated to a 1,000-token budget before
    injection.

- `codex-rs/core/src/context_manager/history.rs`
  - Owns `ContextManager`, the in-memory ordered response-item history.
  - Tracks `history_version`, token usage estimates, a reference context item
    for diffing, and a world-state baseline.
  - `replace`, rollback, compaction, and image replacement are history rewrite
    points and bump/reset cache-sensitive state.

- `codex-rs/core/src/context_manager/updates.rs`
  - Builds model-visible settings diffs for model switch, permissions,
    collaboration mode, multi-agent mode, realtime mode, and personality.
  - Merges adjacent contextual fragments by role to reduce item count and keep
    context grouped.

- `codex-rs/core/src/session/mod.rs`
  - Builds the initial context bundle and per-turn contribution items.
  - Extension context contributors return prompt fragments, which are sorted
    into developer sections, contextual user sections, or separate developer
    messages.
  - World state diffs are rendered from the same step snapshot used to run tools,
    then persisted after the matching model-visible context is recorded.

Coordinator rule of thumb: if a new feature needs to show the model information
on every turn, add a structured context fragment or extension contributor with a
clear cap. If it only changes when settings change, use the settings diff path
instead of re-injecting full text repeatedly.

### Memory Read Path

Memory read behavior is split across a read crate and an extension:

- `codex-rs/memories/read`
  - Owns memory root helpers, memory citation parsing, and read-usage telemetry
    classification.
  - The memory root is `$CODEX_HOME/memories`.

- `codex-rs/ext/memories`
  - Installs memory prompt and tool contributors.
  - On thread start/config change, stores `MemoriesExtensionConfig` in extension
    thread data.
  - When `Feature::MemoryTool` and `config.memories.use_memories` are enabled,
    contributes memory read-path developer instructions.
  - If `config.memories.dedicated_tools` is enabled, exposes dedicated memory
    tools: list, read, search, and add ad-hoc note.

The memory read prompt comes from:

```text
codex-rs/ext/memories/templates/memories/read_path.md
```

That prompt includes the contents of:

```text
$CODEX_HOME/memories/memory_summary.md
```

The summary is truncated before injection using
`MEMORY_TOOL_DEVELOPER_INSTRUCTIONS_SUMMARY_TOKEN_LIMIT`. This is the main
coordination point for keeping memory context useful without making every turn
too large.

Memory read prompt behavior:

- Use memory by default when prior project context is likely relevant.
- Skip memory for clearly self-contained tasks.
- Prefer a quick memory pass over broad scans.
- If memory is used, final answers must include one memory citation block.
- Memory updates are only allowed when the user explicitly asks for them.
- Ad-hoc updates are written under
  `$CODEX_HOME/memories/extensions/ad_hoc/notes/`; do not directly edit
  consolidated memory files.

### Memory Write Path

The reusable write crate is:

```text
codex-rs/memories/write
```

Runtime orchestration still lives in `codex-core` memory startup code.

The pipeline runs asynchronously when a root session starts, only if:

- the session is not ephemeral,
- memory generation is enabled,
- the session is not a sub-agent session,
- the state DB is available.

Phase 1 extracts per-rollout memories:

- claims a bounded set of eligible rollout jobs from the state DB,
- filters rollout content to memory-relevant items,
- sends rollout content to a model with a fixed concurrency cap,
- stores `raw_memory`, `rollout_summary`, and optional slug back to the DB,
- uses retry/backoff instead of hot-looping failures.

Phase 2 consolidates globally:

- claims a single global phase-2 lock before mutating the memories root,
- selects a bounded set of stage-1 outputs,
- syncs `raw_memories.md` and `rollout_summaries/`,
- writes `phase2_workspace_diff.md`,
- runs a dedicated consolidation sub-agent only if the memory workspace changed,
- runs that agent with no approvals, no network, local write access only, and
  collab disabled.

Coordinator rule of thumb: Phase 1 is parallel and per-rollout; Phase 2 is
serialized and global. Do not add cross-thread memory mutation outside the
Phase 2 lock.

### Memory Mode and External Context

Config shape:

```toml
[memories]
disable_on_external_context = true
generate_memories = true
use_memories = true
dedicated_tools = false
```

Behavior:

- `generate_memories = false` stores new/resumed threads with memory mode
  disabled.
- `use_memories = false` skips memory usage instructions in developer prompts.
- `dedicated_tools = true` exposes the memory tools when the feature is enabled.
- `disable_on_external_context = true` lets external context sources mark a
  thread's memory mode as polluted.

MCP tool calls can mark memory mode polluted through
`maybe_mark_thread_memory_mode_polluted` when the MCP server is configured as
memory-polluting. This prevents generated memories from treating external tool
context as clean user/project memory.

Coordinator rule of thumb: if a tool or external source can inject third-party
state into a turn, decide whether it pollutes memory. If it does, wire it through
the existing memory-mode pollution path rather than silently allowing memory
generation to consume it.

### Handoff Guidance for Future Agents

When adding model-visible context:

1. Identify whether the context is startup-only, per-turn, settings-diff, world
   state, or memory-derived.
2. Put durable context structs under `codex-rs/core/src/context` and implement
   `ContextualUserFragment`.
3. Add hard caps before rendering; prefer truncation at the source.
4. Preserve markers for injected user-context fragments so filtering and
   rollback can recognize them.
5. Prefer extension contributors for feature-owned context and tools.
6. Keep memory read and memory write separated. Read-path prompt/tool work
   belongs in `ext/memories` or `memories/read`; write-pipeline work belongs in
   `memories/write` or the existing core orchestration.
7. For agent logic changes that alter model-visible behavior, prefer core
   integration tests under `codex-rs/core/tests/suite`.

Escalate for manual review when:

- a new context item can cross 1K tokens,
- context is not clearly bounded,
- a change rewrites history rather than appending/diffing,
- a feature injects external context but does not define memory pollution
  behavior,
- a memory write path can run concurrently without the established DB claim or
  global phase-2 lock.

## Plugins and Skills

Codex plugins and skills are capability packaging mechanisms. They are not the
same thing as the internal Rust extension API and they are not a general dynamic
native-code plugin ABI.

### Plugin Package Shape

A plugin is rooted at a directory with a manifest:

```text
my-plugin/
  .codex-plugin/plugin.json
  skills/
  .mcp.json
  .app.json
  hooks/hooks.json
  assets/
```

The manifest is parsed by `codex-rs/core-plugins` and represented by
`codex-rs/plugin/src/manifest.rs`.

Core manifest fields:

- `name`, `version`, `description`, and `keywords` identify the package.
- `skills` points to skill resources.
- `mcpServers` points to MCP server config or contains MCP server config inline.
- `apps` points to app connector metadata.
- `hooks` points to hook config.
- `interface` carries UI/catalog metadata such as display name, descriptions,
  category, capabilities, default prompts, colors, icons, logos, and screenshots.

Useful defaults in the loader:

- skills path: `skills`
- MCP config path: `.mcp.json`
- app config path: `.app.json`
- hooks path: `hooks/hooks.json`
- plugin-local config path: `config.toml`

Plugin resource paths are resolved under the plugin root. The provider layer
rejects resources that escape that root, so manifests should use relative paths
inside the package.

### Plugin Load Flow

The active plugin set comes from the config layer stack and marketplace/install
state.

Important code paths:

- `codex-rs/core-plugins/src/manager.rs`
  - Builds plugin config input from installed, remote, global catalog, cache, and
    marketplace state.
  - Controls whether plugins and remote plugins are enabled.

- `codex-rs/core-plugins/src/loader.rs`
  - Loads configured plugins from the layer stack.
  - Parses `.codex-plugin/plugin.json`.
  - Loads plugin skills, MCP server configs, app configs, and hooks.
  - Deduplicates MCP server names; duplicate server names are skipped with a
    warning.

- `codex-rs/plugin/src/provider.rs`
  - Resolves selected plugin roots into inert descriptors.
  - Validates package-root containment.
  - Does not activate plugin behavior by itself.

Coordinator rule of thumb: plugin loading discovers and validates resources;
feature-specific loaders decide how those resources become context, tools,
hooks, or UI metadata.

### Skills

Skills are prompt-and-resource packages used to teach Codex a workflow,
domain-specific instructions, scripts, templates, references, or assets.

Relevant code paths:

- `codex-rs/skills/src/lib.rs`
  - Installs embedded system skills under `$CODEX_HOME/skills/.system`.

- `codex-rs/ext/skills/src/extension.rs`
  - Contributes the available-skills list to model-visible context.
  - Selects explicitly mentioned skills such as `$skill-name`.
  - Injects selected skill instructions with per-skill context limits.
  - Contributes executor skill world state for selected capability roots.
  - Exposes skill tools when skill tooling is enabled.

- `codex-rs/skills/src/assets/samples/skill-creator/references/openai_yaml.md`
  - Documents optional `agents/openai.yaml` metadata.
  - Supports UI metadata, default prompt text, MCP tool dependencies, and
    `policy.allow_implicit_invocation`.

Skill invocation behavior:

- The model sees a bounded list of available skills.
- Explicit mentions such as `$skill-name` force that skill into the turn.
- If `allow_implicit_invocation = false`, the skill is not injected by default
  but still works when explicitly mentioned.
- Skill instructions and related context are budgeted. Long descriptions or
  prompts are shortened rather than injected unbounded.

Skill dependencies:

- `agents/openai.yaml` currently supports tool dependencies of type `mcp`.
- MCP dependencies can use streamable HTTP with a URL, for example a GitHub MCP
  endpoint.
- This means a skill can tell Codex that a tool server is needed, but the MCP
  server is still the executable/network boundary.

### Internal Extension API

`codex-rs/ext/extension-api` is the internal Rust extension surface used by
built-in features such as memories, skills, web search, and image generation.

It exposes contributor traits for:

- config,
- context,
- thread lifecycle,
- turn input,
- tools,
- tool lifecycle,
- world state,
- token usage.

External plugin packages should not be treated as dynamically loaded Rust
extensions. They contribute declarative resources that the existing loader and
extension machinery consume.

### HTTP Server Question

There are two different directions that are easy to confuse.

Codex calling a plugin-provided HTTP service:

- Yes, this fits the plugin model when the HTTP service speaks MCP.
- The plugin can declare the MCP server in `.mcp.json` or inline under
  `mcpServers`.
- The MCP server can be an externally hosted streamable HTTP endpoint or a local
  process depending on the MCP config.
- In this design, Codex is the client and the MCP server exposes tools to Codex.

External callers calling Codex over HTTP:

- This is not what plugins are for.
- A plugin manifest does not grant an activation lifecycle for an arbitrary HTTP
  server that exposes Codex itself.
- Use or extend `codex-rs/app-server` and `codex-rs/app-server-protocol` for an
  HTTP/JSON-RPC control surface over Codex threads.
- A wrapper service can also call `codex exec`, but app-server is the native
  architecture for programmatic thread/turn APIs.

Concrete architecture choices:

1. If the goal is "give Codex new tools over HTTP", package or reference an MCP
   server through a plugin.
2. If the goal is "let my app call Codex with HTTP requests", build against
   app-server or add the missing app-server API.
3. If the goal is "ship a plugin that starts a local HTTP MCP server", keep the
   plugin as the descriptor and make lifecycle, ports, auth, and process startup
   explicit in the MCP/server integration. Do not assume plugin load alone means
   arbitrary server startup.

Security and coordination notes:

- Any external MCP/app context that can affect memory generation must define
  memory pollution behavior.
- Keep plugin resources rooted inside the package.
- Treat hooks and MCP servers as execution boundaries that need explicit trust,
  auth, and review.
- Avoid adding provider-specific model behavior through plugins. Model routing
  belongs in provider config or provider/adaptor code.

## Verification Already Run

Passed:

```bash
just fmt
just test -p codex-utils-cli avalai
just test -p codex-cli avalai
just test -p codex-exec resume_accepts_avalai_after_subcommand
cargo run -p codex-cli --bin codex -- exec resume --avalai --help
agent-coordinator/e2e/avalai-codex-e2e.sh
```

Live AvalAI smoke tests:

```bash
CODEX_HOME=/tmp/codex-avalai-home \
cargo run -p codex-cli --bin codex -- exec --avalai \
  --cd /home/ubuntu/codex-agent/codex \
  --sandbox workspace-write \
  --ephemeral \
  --json \
  "Run ls in the current directory using the shell, then respond with the exact ls output."
```

Initial observation:

- `AVALAI_API_KEY` exists in the environment, but its value is the literal
  placeholder `null` with length 4.
- The network-enabled run reached `https://api.avalai.ir/v1/responses`.
- AvalAI returned `401 Unauthorized` because the provided API key was `null`.
- The request did not reach a model turn, so the model did not get to run `ls`.
- The run also reported that local model metadata for `deepseek-v4-pro` was not
  found; that warning is separate from the auth failure and the model slug still
  needs live confirmation.

Follow-up with a real AvalAI key:

- Direct non-streaming `/v1/responses` probe with `deepseek-v4-pro` returned
  HTTP 200 and model output `OK`.
- Direct streaming `/v1/responses` probe returned SSE events through
  `response.completed`.
- Direct streaming probe with one tiny `exec_command` function tool returned a
  function call with arguments `{"cmd": "ls"}`.
- Full default `codex exec --avalai` still failed under peak-load / maximum
  usage-size errors before the model emitted a tool call.
- A reduced-context Codex run succeeded when optional features, plugins, app
  tools, image generation, tool suggestions, multi-agent, guardian approval,
  goals, and skill instructions were disabled.

Successful Codex smoke command shape:

```bash
CODEX_HOME=/tmp/codex-avalai-home-realkey \
AVALAI_API_KEY="$AVALAI_API_KEY" \
cargo run -p codex-cli --bin codex -- exec \
  --ignore-user-config \
  --avalai \
  --cd /home/ubuntu/codex-agent/codex \
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
```

The model called:

```text
/bin/bash -lc ls
```

The command completed with exit code 0 and this aggregated output:

```text
AGENTS.md
BUILD.bazel
CHANGELOG.md
LICENSE
MODULE.bazel
MODULE.bazel.lock
NOTICE
README.md
SECURITY.md
agent-coordinator
announcement_tip.toml
bazel
cliff.toml
codex-cli
codex-rs
defs.bzl
docs
flake.lock
flake.nix
justfile
package.json
patches
pnpm-lock.yaml
pnpm-workspace.yaml
rbe.bzl
scripts
sdk
third_party
tools
workspace_root_test_launcher.bat.tpl
workspace_root_test_launcher.sh.tpl
```

Conclusion: AvalAI auth, `deepseek-v4-pro`, streaming, and basic function
calling work. The remaining compatibility/performance issue is that the full
default Codex request envelope can exceed AvalAI's peak-load usage limits, so
production use may need feature gating, smaller tool/context exposure, or an
AvalAI/provisioned-throughput setting.

Deeper coordinator-style run:

- Ran a reduced-context AvalAI-backed `codex exec` prompt that required the
  model to inspect the repository implementation.
- The model used `rg` and `cat` through shell tools.
- It identified the shared flag definition, shortcut provider constants, exec
  wiring, TUI wiring, archive-command wiring, and parser tests.
- The turn completed successfully with multiple tool calls.

Coordinator E2E script result:

- `agent-coordinator/e2e/avalai-codex-e2e.sh` passed with a real AvalAI key.
- Covered direct non-streaming text, direct streaming text, direct streaming
  function-call event shape, and reduced-context `codex exec --avalai`.
- The final Codex gate reached `turn.completed` after executing `ls`.

The full `just test -p codex-exec` build completed, but 18 integration tests
failed in this sandbox because `wiremock` could not bind local OS ports:

```text
PermissionDenied: Failed to bind an OS port for a mock server
```

Those failures were environment-related and not specific to the AvalAI parser
change. The socket-free parser tests passed.

## Current Git Status Notes

The shortcut implementation includes new files that must be tracked before the
change can be committed:

```text
codex-rs/utils/cli/src/model_provider_shortcuts.rs
codex-rs/utils/cli/src/model_provider_shortcuts_tests.rs
```

There are also unrelated dirty files in the working tree from other app-server,
profile, protocol, TUI, and schema work. Do not revert them unless explicitly
asked.

## Recommended Next Steps

1. Keep `agent-coordinator/e2e/avalai-codex-e2e.sh` as the coordinator's
   minimum E2E gate for AvalAI-backed Codex.
2. Use `avalai-codex-reduced` as the default automated profile until full
   default Codex requests are reliable under AvalAI limits.
3. If the endpoint is `/v1/responses` compatible, keep this as a provider
   shortcut only.
4. If the endpoint is not compatible, design a separate provider compatibility
   path rather than changing the generic OpenAI Responses behavior.

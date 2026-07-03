# Project Context and Memory Plan

Last updated: 2026-07-03

## Goal

Add a simple user-facing way to run Codex with project-scoped durable state:

```bash
codex --project xyz
codex exec --project xyz "..."
```

The intended behavior is that Codex creates or reuses a project-scoped store for
the current repository/directory so future runs can reuse memory, session
history, summaries, and eventually indexing artifacts instead of rediscovering
the same project facts.

## Current State

This checkout does not expose a top-level `codex --project xyz` flag.

Existing related pieces:

- `codex profiles run --project --project-id xyz --project-dir DIR -- ...`
  - Implemented in `codex-rs/cli/src/profile_manager_cmd.rs`.
  - Uses a stable per-project `CODEX_HOME`.
  - Stores project homes under the managed profiles root, currently defaulting
    to `~/.config/codex-switch/projects/<id>`.
  - Copies the selected profile's `auth.json` into the project home.
  - Writes marker files:
    - `.codex-profile-account`
    - `.codex-profile-project-root`

- `codex --best`
  - Implemented in `codex-rs/cli/src/main.rs`.
  - Selects the best managed account profile and prepares a project home for the
    current project.
  - Only applies to interactive TUI startup.

- `CODEX_HOME`
  - Owns durable Codex state.
  - Public manual says it stores config, auth, logs, sessions, skills, and
    standalone package metadata.
  - Memory read/write code stores memories under `CODEX_HOME/memories`.
  - Rollout/session code stores sessions under `CODEX_HOME/sessions` and
    archived sessions under `CODEX_HOME/archived_sessions`.

- Project trust config
  - `[projects."<path>"] trust_level = "trusted"` controls project trust/config
    loading behavior.
  - It is not a project memory namespace.
  - Project-local profile selectors are intentionally ignored.

What is missing:

- No direct `codex --project xyz` or `codex exec --project xyz`.
- No project-scoped state selection that works uniformly for TUI, exec, resume,
  archive, app-server, and CLI debug paths.
- No built-in codebase index tied to a project namespace.
- No bounded project-summary context contributor that always loads from the
  selected project state.

## Recommended Product Shape

Use a named project flag with root safety:

```bash
codex --project xyz
codex exec --project xyz "fix the parser"
codex resume --project xyz --last
```

Semantics:

- `--project xyz` selects a project namespace named `xyz`.
- Codex resolves the active project root from `--cd`, `--project-dir`, or the
  current working directory. Prefer the git root when available.
- If the project namespace does not exist, create it and bind it to that root.
- If it exists and is bound to the same root, reuse it.
- If it exists but points to another root, fail with a clear message and offer a
  generated id or an explicit rebind command.

This avoids accidentally sharing memories between unrelated directories that use
the same friendly project name.

## Account Profile Switching

Project-scoped state should survive account profile changes by default.

The existing `codex profiles run --project` behavior already works this way:

- project homes are keyed by project id under `projects/<id>`,
- selecting a different profile reuses the same project home,
- `auth.json` is copied from the selected profile into that project home,
- `.codex-profile-account` is updated to record the currently selected profile,
- existing project sessions and memories remain in the same home.

That is the right default for the requested "experience" behavior: the project
remembers what Codex learned even if the user changes from one authenticated
account profile to another.

However, this has an account-boundary implication. A different account profile
will be able to see the same local project memories and prior session-derived
state. The product should make that explicit and provide an isolation escape
hatch.

Recommended semantics:

- Default: `--project xyz` shares local project memory across account profiles.
- Isolation option: `--project xyz --project-account-scope profile` or a config
  setting stores state under `projects/<id>/accounts/<profile>`.
- Migration option: `codex project split-account xyz` can copy or move existing
  memories/sessions into account-scoped state if a user later wants separation.
- Metadata: store both project root and last-used account/profile in marker
  files so diagnostics can explain what happened.

## Implementation Plan

### Phase 1: Project Home Resolver

Extract or reuse the existing project-home logic from:

```text
codex-rs/cli/src/profile_manager_cmd/project.rs
codex-rs/cli/src/profile_manager_cmd/root.rs
```

Create a small shared module or crate that can:

- validate project names with the existing profile-name rules,
- resolve a project root from cwd/git root,
- create or reuse a project home,
- write marker files for project name and root,
- reject root mismatches,
- copy or link required auth material safely.

Open design choice:

- MVP can use a project-specific `CODEX_HOME`.
- Longer-term cleaner design is a separate `project_state_home` so base
  user-level config/auth remains global while sessions/memories/indexes are
  project-specific.

### Phase 2: CLI Surface

Add shared CLI options:

```text
--project <PROJECT_ID>
--project-dir <DIR>
```

Wire them through the same paths as other shared options:

- `codex-rs/utils/cli/src/shared_options.rs`
- `codex-rs/cli/src/main.rs`
- `codex-rs/exec/src/lib.rs`
- `codex-rs/tui/src/lib.rs`
- resume/archive/delete/unarchive/fork flows

Important: `--project` must be resolved before config loading if it changes
`CODEX_HOME` or state-root selection.

### Phase 3: State Routing

For the MVP, project mode can set the effective Codex home to the project home.
That immediately scopes:

- sessions,
- archived sessions,
- memories,
- state DB when `CODEX_SQLITE_HOME`/`sqlite_home` do not override it,
- skills and plugin install state if those are allowed in the project home.

If preserving global config/auth is required, add an explicit state-root field
instead:

```rust
project_state_home: Option<AbsolutePathBuf>
```

Then update:

- memory roots,
- rollout/session store roots,
- SQLite default root,
- app-server state initialization,
- thread listing/resume/archive operations.

### Phase 4: Project Memory Context

Do not rely only on raw memories. Add a bounded project context layer:

```text
<project-home>/project_context/summary.md
<project-home>/project_context/facts.jsonl
<project-home>/project_context/index/
```

Start with `summary.md`:

- generated from prior sessions, `AGENTS.md`, key config files, and repo
  metadata,
- hard capped before model injection,
- injected through a context contributor, not by rewriting history,
- updated asynchronously or on explicit command.

Follow existing context rules:

- bounded items,
- no individual item over 10K tokens,
- review any item that can exceed 1K tokens,
- no history rewrites,
- structs under `core/context` implementing `ContextualUserFragment`.

### Phase 5: Optional Indexing

Add indexing after project-home state is solid.

Recommended first version:

- file tree snapshot,
- `AGENTS.md` and `.codex/config.toml` digest,
- language/package manifest digest,
- recently touched files,
- symbol/search cache only if cheap and bounded.

Avoid a broad embedding or full-code index in the first stage unless there is a
clear retrieval API and invalidation strategy.

Store index artifacts under:

```text
<project-home>/project_index/
```

Invalidate based on:

- git HEAD,
- dirty worktree hash/sample,
- manifest mtimes,
- explicit `codex project refresh`.

### Phase 6: Commands

Add management commands:

```bash
codex project current
codex project path xyz
codex project list
codex project reset xyz --memories
codex project refresh xyz
```

Keep destructive operations explicit. Do not silently delete memories or
sessions.

## Testing Plan

Parser tests:

- `codex --project xyz`
- `codex exec --project xyz`
- `codex resume --project xyz --last`
- root `--project` inherited by subcommands where appropriate
- invalid project names rejected

Unit tests:

- project id validation,
- project root resolution,
- first-run marker files,
- root mismatch rejection,
- auth copy/link behavior.

Integration tests:

- two project names in the same repo use separate memory/session roots,
- same project name in a different repo is rejected,
- sessions written under the selected project home,
- `memory_root(config.codex_home)` points to the selected project home in MVP,
- resume/archive/list operate within the selected project state,
- `--project` and `--avalai` compose because both are CLI shortcut layers.

E2E:

```bash
AVALAI_API_KEY=... codex --project xyz --avalai "inspect this repo"
AVALAI_API_KEY=... codex --project xyz --avalai "what did you learn last time?"
```

The second run should see bounded project memory/context without needing to redo
basic discovery.

## Risks

- Switching `CODEX_HOME` also switches config/auth/skills/plugin state. This is
  simple but may surprise users.
- Project memory can become stale or misleading without invalidation.
- Full-code indexing can blow context or disk budgets if not hard capped.
- Sharing one project name across unrelated directories can leak context unless
  root binding is enforced.
- Memory generation is asynchronous and feature-gated, so project memory should
  not be the only project context mechanism.

## Recommendation

Build the feature in this order:

1. Add `--project <id>` as a friendly wrapper over a project-scoped state home.
2. Make it work across TUI, exec, resume, and archive flows.
3. Add tests proving sessions and memories land in the project home.
4. Add a bounded `project_context/summary.md` contributor.
5. Add indexing only after the project-state boundary is reliable.

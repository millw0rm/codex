# Agent Coordinator Entry Point

Last updated: 2026-07-03

## Operating Model

Codex is the coordinator and controller. It owns planning, decomposition,
quality gates, code edits, tests, final synthesis, and user communication.

Cursor is a delegated data-gathering worker. Use it through the
`cursor-session` MCP tool for bounded research and low-risk inspection work
where the expected output is evidence, URLs, facts, command output summaries, or
candidate files to inspect. Cursor should not be the source of final authority;
Codex validates important claims before acting on them.

Goal: spend the expensive Codex context and reasoning budget on coordination and
judgment, while sending cheap, bounded discovery loops to Cursor.

## Default Flow

1. Codex receives the task and decides what information is missing.
2. Codex delegates bounded data-gathering subtasks to Cursor with explicit
   success criteria and output limits.
3. Cursor returns concise findings with evidence.
4. Codex checks the key evidence, resolves conflicts, and decides the next
   action.
5. Codex performs edits, tests, reviews, and final reporting.

This keeps Cursor in the worker role and Codex in the accountable role.

## Cursor Delegation Policy

Use Cursor first for:

- finding login pages, documentation pages, changelog entries, issue references,
  package metadata, or public website behavior;
- broad but bounded repo scans, such as "find the files likely responsible for
  X and explain why";
- cheap comparison work, such as checking several URLs or candidate files and
  returning a ranked shortlist;
- preliminary bug reproduction notes when the expected output is observations,
  not code changes;
- extracting source-backed facts that Codex can later verify.

Keep Codex responsible for:

- making architecture decisions;
- writing or modifying files;
- applying repo-specific rules from `AGENTS.md`;
- deciding whether external evidence is trustworthy;
- running required verification;
- producing the final answer to the user.

Do not use Cursor as the default worker for:

- tasks involving secrets or private credentials beyond the mounted Cursor auth;
- destructive actions;
- unbounded crawling or scraping;
- high-stakes legal, medical, financial, or security conclusions without Codex
  verification;
- final code review signoff.

## Tool Contract

The detailed Cursor contract is in
[`cursor-session-coordination.md`](cursor-session-coordination.md).

Core rule:

```text
Codex asks. Cursor gathers. Codex verifies and decides.
```

Default `cursor-session` behavior:

- runs `cursor-agent`;
- uses Cursor auth from `cursor-home`, defaulting to `/cursor-home`;
- defaults to the MCP server's resolved `Config.cwd`, which is the same
  workspace Codex uses;
- lets a tool-call `cwd` override that default when needed;
- defaults to read-oriented `ask` mode;
- returns bounded text output for Codex to inspect.

## Prompt Shape

Delegation prompts should be narrow and evidence-driven:

```text
Use your available tools to check <target>.
Do not edit files.
Return:
1. direct answer;
2. evidence with URLs, file paths, commands, or snippets;
3. confidence and unresolved gaps.
Keep the answer under <N> bullets.
```

For web discovery:

```text
Use your available tools to check https://example.com and find the login page.
Do not edit files.
Return the final URL, how the login UI is reached, redirects observed, and
brief evidence from the page or HTTP responses.
```

For repo discovery:

```text
Inspect this repository and identify the files most likely responsible for
<behavior>.
Do not edit files.
Return a ranked list of paths, the evidence for each, and the next Codex action
you recommend.
```

## Efficiency Rules

- Prefer one clear Cursor prompt over a long chain of vague prompts.
- Ask for evidence, not narrative.
- Ask Cursor to rank or shortlist when many candidates exist.
- Keep `output-max-bytes` at the default unless the task truly needs more;
  currently output is capped at 16,000 bytes.
- Give Cursor a local `cwd` only when the subtask needs a different workspace.
- Treat Cursor output as external context. Persist it into memory only after
  Codex has verified it and the user actually wants durable memory.

## Quality Gates

Before Codex acts on Cursor output:

- verify URLs or paths that drive decisions;
- inspect files before editing them;
- confirm redirects or status codes when web behavior matters;
- cross-check surprising claims;
- reject any Cursor suggestion that conflicts with repo instructions,
  permissions, or the user's latest request.

## Related Notes

- [`project-context-memory-plan.md`](project-context-memory-plan.md) covers
  project-scoped state, memories, and bounded context.
- [`codex-avalai-deepseek-notes.md`](codex-avalai-deepseek-notes.md) covers
  lower-cost Codex execution profiles and reduced-context E2E gates.

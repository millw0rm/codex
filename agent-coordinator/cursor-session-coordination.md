# Cursor Session Coordination

Last updated: 2026-07-03

## Purpose

`cursor-session` lets Codex ask Cursor Agent to perform bounded research or
analysis using a separate Cursor login profile. In the coordinator architecture,
this is the cheap data-gathering lane:

```text
Codex = coordinator, controller, verifier, editor
Cursor = delegated data-gathering worker
```

The intended use is not "let Cursor run the job." The intended use is "let
Cursor gather the evidence Codex needs to run the job well."

## Current Wiring

The MCP server exposes a `cursor-session` tool.

Important local files:

- `codex-rs/mcp-server/src/cursor_session.rs`
  - Defines the tool schema and runs `cursor-agent`.
  - Prepares the child process command.
  - Sets Cursor-specific home/cache environment variables.
  - Reads stdout/stderr with byte caps and returns structured output.

- `codex-rs/mcp-server/src/message_processor.rs`
  - Adds `cursor-session` to `tools/list`.
  - Routes `tools/call` requests to the Cursor handler.
  - Passes the MCP server's resolved `Config.cwd` as the default Cursor cwd.

- `codex-rs/mcp-server/tests/suite/cursor_session_tool.rs`
  - Verifies the tool is exposed.
  - Verifies missing args route to the handler.
  - Verifies omitted `cwd` runs Cursor in the configured workspace.

## Tool Input

The tool uses kebab-case JSON fields:

```json
{
  "prompt": "Required task for Cursor.",
  "cwd": "/optional/workspace",
  "command": "cursor-agent",
  "cursor-home": "/cursor-home",
  "mode": "ask",
  "model": "auto",
  "timeout-seconds": 900,
  "output-max-bytes": 16000
}
```

Only `prompt` is required.

Field behavior:

- `prompt`: task or question to send to Cursor Agent.
- `cwd`: working directory for Cursor Agent. If omitted, defaults to the MCP
  server's resolved `Config.cwd`, matching the working directory Codex uses.
  If provided, it overrides the default. Relative values are resolved by the
  child process.
- `command`: command to run. Defaults to `CURSOR_SESSION_AGENT_COMMAND` or
  `cursor-agent`.
- `cursor-home`: Cursor login-profile home. Defaults to
  `CURSOR_SESSION_HOME` or `/cursor-home`.
- `mode`: Cursor mode. Defaults to `CURSOR_SESSION_MODE` or `ask`.
- `model`: Cursor model. Defaults to `CURSOR_SESSION_MODEL` or `auto`.
- `timeout-seconds`: maximum runtime. Defaults to
  `CURSOR_SESSION_TIMEOUT_SECONDS` or 900.
- `output-max-bytes`: stdout/stderr byte budget. Defaults to
  `CURSOR_SESSION_OUTPUT_MAX_BYTES` or 16,000, and is capped at 16,000.

## Command Shape

The handler runs Cursor Agent as:

```bash
cursor-agent \
  -p \
  --trust \
  --mode "$MODE" \
  --model "$MODEL" \
  --output-format text \
  "$PROMPT"
```

Additional words from `command` are preserved before these arguments, so a
configured command like `cursor-agent --extra` keeps `--extra`.

## Authentication and Environment

Cursor auth is intentionally separate from Codex auth.

Required auth file:

```text
<cursor-home>/.config/cursor/auth.json
```

Default:

```text
/cursor-home/.config/cursor/auth.json
```

The child environment is cleared, then rebuilt with only a narrow allowlist:

- `PATH`
- locale variables: `LANG`, `LC_ALL`
- proxy variables: `ALL_PROXY`, `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`, and
  lowercase variants
- TLS variables: `SSL_CERT_FILE`, `SSL_CERT_DIR`

The handler then sets:

- `HOME=<cursor-home>`
- `XDG_CONFIG_HOME=<cursor-home>/.config`
- `XDG_CACHE_HOME=<cursor-home>/.cache`
- `NPM_CONFIG_CACHE=<cursor-home>/.npm`

Parent process secrets such as `CURSOR_API_KEY` are not inherited unless they
are explicitly part of the allowed environment. The expected auth path is the
mounted Cursor login profile, not a Codex API key.

## Output Contract

The structured output contains:

```json
{
  "content": "stdout text",
  "stderr": "stderr text",
  "exitCode": 0,
  "timedOut": false,
  "stdoutTruncated": false,
  "stderrTruncated": false
}
```

Codex should treat `content` as a research result, not as a final answer. If
`timedOut`, `exitCode`, or truncation fields indicate a partial result, Codex
should either narrow the prompt and retry or switch to direct verification.

## Delegation Patterns

### Web Page Discovery

Use Cursor for cheap site inspection, route discovery, redirects, and source
evidence:

```json
{
  "prompt": "Use your available tools to check https://numberland.ir and find its login page URL. Do not edit files. Return the final URL, redirects observed, and brief evidence."
}
```

Codex should verify the final URL before relying on it.

### Documentation Research

```json
{
  "prompt": "Find the official docs for <feature>. Return the canonical URL, the relevant version/date, and the 3 facts Codex needs. Do not edit files."
}
```

Codex should open or inspect the cited source if the answer affects code,
dependencies, APIs, legal behavior, or money.

### Repository Triage

```json
{
  "prompt": "Inspect this repository and identify the files most likely responsible for <behavior>. Do not edit files. Return a ranked path list with evidence and a suggested next Codex action."
}
```

Codex then reads the candidate files itself before editing.

### Multi-Candidate Comparison

```json
{
  "prompt": "Compare these candidate files or URLs: <list>. Return the strongest match, why, and what evidence would falsify it. Do not edit files."
}
```

This is useful when Codex needs a shortlist but not final judgment.

## Coordinator Decision Rules

Delegate to Cursor when:

- the task is mostly discovery;
- the expected answer can be checked from evidence;
- the result can fit in a bounded response;
- mistakes are cheap because Codex will verify before acting.

Keep the task in Codex when:

- edits are required;
- repo rules or nuanced architecture decisions dominate;
- the answer will directly affect security, privacy, legal, financial, or
  production behavior;
- the task needs privileged local state that Cursor should not receive;
- the required result cannot be bounded.

## Prompting Rules

Every Cursor prompt should include:

- exact target;
- explicit "Do not edit files";
- expected output format;
- evidence requirement;
- cap on breadth or bullets;
- confidence or unresolved gaps when useful.

Preferred template:

```text
Use your available tools to <task>.
Do not edit files.
Return:
1. answer;
2. evidence with URLs, file paths, commands, or snippets;
3. confidence and unresolved gaps.
Keep it under <N> bullets.
```

Avoid prompts like:

```text
Research this thoroughly.
Figure everything out.
Do whatever is needed.
```

Those produce expensive, hard-to-verify output.

## Memory and Context Handling

Cursor output is external context. Treat it the same way as web search, MCP
tool output, or another agent's notes:

- do not inject unbounded Cursor output into every future turn;
- summarize and cap anything that becomes project context;
- verify before writing to durable memory;
- mark Cursor-derived tool context as memory-polluting if the MCP config path
  supports that for the calling server;
- never let Cursor output rewrite history.

If Cursor finds a fact that should become durable project memory, Codex should
write the verified, minimal fact through the normal memory path. Do not store a
raw transcript unless the user explicitly asks for that artifact.

## Quality Loop

For high-quality low-cost work:

1. Codex narrows the question.
2. Cursor gathers facts and evidence.
3. Codex validates the decisive evidence.
4. Codex acts or asks a narrower follow-up.
5. Codex reports the result with clear confidence.

Use retries only to narrow scope, not to ask the same broad question again.

## Failure Handling

Common failures:

- Missing auth:
  - `cursor-session auth file is not available at ...`
  - Fix by mounting or selecting the correct `cursor-home`.

- Cursor network failure:
  - Cursor Agent cannot reach Cursor services such as `api2.cursor.sh`.
  - In a sandboxed run, this may require network approval.

- Target network failure:
  - Cursor reaches its model service but cannot reach the target website or API.
  - Ask Cursor to report exact status codes or DNS errors, then Codex can decide
    whether direct verification is needed.

- Timeout:
  - Narrow the prompt or lower the requested breadth.
  - Do not simply increase timeout for vague research.

- Truncated output:
  - Ask Cursor for a ranked summary or a specific missing slice.
  - Keep the default cap unless a larger result is essential.

## Example: Numberland Login Page

Prompt:

```json
{
  "prompt": "Use your available tools to check https://numberland.ir and find its login page URL. Do not edit files. Return the login URL and brief evidence for how you found it."
}
```

Observed Cursor result:

- primary login surface is `https://numberland.ir/`;
- the login UI opens via the homepage's Persian login/register control;
- the source references `https://numberland.ir/loginpage.php?logintype=yektanet`;
- `/loginpage.php` redirects back to the homepage, so it is not a persistent
  standalone login page.

Coordinator takeaway:

```text
Use https://numberland.ir/ and open the login/register modal.
```

Codex should still re-check the site if this fact becomes important later,
because website routing can change.

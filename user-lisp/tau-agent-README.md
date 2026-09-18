# Tau-agent

A standalone Markdown coding agent for Emacs 30.1+, using ChatGPT OAuth.
It requires `markdown-mode` and `curl`; browser login also uses `head` and
`/dev/urandom` for PKCE randomness on this Linux setup. It does not load gptel
or transient.

Run `M-x tau-agent` from your project to start a conversation. The header
The first header row shows the model, reasoning effort, and project directory.
The second row uses Emacs's tab line to show activity with a status emoji and
token usage. `in`/`out` describe the latest response;
`cache` is the cached subset of input and `reason` the reasoning subset of
output. `Σ` adds reported input and output across requests (including tool
continuations), not the current context size. Missing usage is shown as `?`;
totals include only reported usage. Stats update when each request ends and
are preserved in saved sessions.

| Command | Binding | Purpose |
| --- | --- | --- |
| `tau-agent-send` | `C-c C-c` | Send the final user draft |
| `tau-agent-cancel` | `C-c C-k` | Stop the current request or tool |
| `tau-agent-set-reasoning-effort` | `C-c C-r` | Change reasoning effort |
| `tau-agent-set-model` | `C-c C-m` | Change model |
| `tau-agent-save-session` | `C-x C-s` | Save structured JSON |
| `tau-agent-load-session` | | Resume a saved conversation |
| `tau-agent-edit-system-prompt` | | Jump to this conversation's System message |
| `tau-agent-refresh-tools` | | Refresh the generated tool list |
| `tau-agent-toggle-tool` | `TAB` | Expand/collapse a tool request or result |
| `tau-agent-insert-reference` | `@` | Complete a project-relative path |
| `tau-agent-login` | | Browser OAuth login; prefix argument selects device login |

The defaults are `gpt-5.6-luna` and `medium` reasoning. Reasoning effort is a
buffer-local setting, appears in the header, is saved with the session, and
is sent on every request, including tool continuations. The selected model
must support the chosen effort; server errors are displayed without silently
changing the setting. Reasoning text stays hidden; encrypted reasoning items
are preserved for protocol continuity.

System, user, and assistant message bodies can be edited when idle. Later history is
retained, and subsequent requests use the edited text. Message boundaries
and tool records are protected by overlays. Fringe colors distinguish the system, users,
assistant replies, tool calls, tool results, and errors. Text headings also
identify roles in terminal Emacs. Markdown fontification uses its normal
text properties; tau-agent's message state and protections use overlays.
Tool requests and results start collapsed to a short preview. Press `TAB`
on their heading or body to toggle, including while a turn is running.
Elsewhere, `TAB` keeps Markdown's normal behavior. Set
`tau-agent-collapse-tools` to nil to start expanded instead. Folding only
changes display: full text remains in model context and saved sessions.

The four tools (`shell`, `read`, `edit`, `write`) run automatically in the
captured project root. Cancellation does not undo file changes or commands
that already ran. It records interrupted calls and never automatically
replays them. Tool errors are returned to the model, while transport errors
end the turn visibly. There is no automatic history truncation or compaction.

Each conversation starts with its own editable System message, marked with a
coral fringe (`tau-agent-system-face`). It contains the base
instructions, working directory, and root `AGENTS.md`, captured when the
conversation starts. Its current text is sent as API instructions on each
request, separately from chat history. Saved sessions restore it at the top
of the buffer, including sessions saved before the inline display existed.
Typing `@` completes files from `project-files`, relative to `project-root`.
Outside a project, it offers files directly in `default-directory`, relative
to that directory. It inserts only the path, not the file's contents. Cancel
completion to leave a literal `@`.

A read-only Tools section below the System message lists the configured
tools, their arguments (`?` marks optional arguments), and descriptions.
Its slate-colored fringe uses `tau-agent-tools-face`. The list refreshes
before each request; after changing `tau-agent-tools` manually, you can also
run `tau-agent-refresh-tools`. It is generated again when loading a session,
and is not duplicated in the system instructions or conversation sent to
the model. Tool schemas continue to be sent through the API's tools field.

Sessions are versioned JSON with message text, tool/protocol records, the
draft, system prompt, working directory, model, and reasoning effort. They
contain no OAuth credentials. Save only while idle; cancel an active turn
first. Loading reconstructs overlays without executing tools or making a
request. Use `tau-agent-load-session` rather than visiting the JSON as a chat
buffer. Ordinary Markdown exports are not resumable sessions.

OAuth reuses `.cache/gptel-openai/openai-oauth-token` under
`user-emacs-directory`, avoiding duplicate rotating refresh tokens. Set
`tau-agent-token-file` to use a different location. Login and refresh use
Emacs URL support; conversation requests stream through curl. Token writes
are atomic with mode 0600, and curl authorization headers live in a private
temporary configuration file removed when the request ends.

To add a tool, construct a `tau-agent-tool` with `tau-agent-make-tool` and
include it in the buffer-local `tau-agent-tools` list. Supply `:name`,
`:description`, `:args`, and `:function`. Argument specs use `:name`, `:type`,
and optional `:optional t`, plus JSON Schema constraints. Values are passed
to the function in argument-spec order. For `:async t`, the first function
argument is a callback accepting one result string; return the subprocess
so cancellation can stop it. The four built-in tools are examples.

Run `make tau-test` for offline ERT tests, `make byte-compile` for compilation
with warnings treated as errors, and `make checkdoc` for docstring checks.

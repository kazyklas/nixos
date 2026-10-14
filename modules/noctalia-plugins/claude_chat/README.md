# Claude Chat (Noctalia plugin)

A chat panel for [Noctalia](https://noctalia.dev) 5.x that talks to Claude through the
**Claude Code CLI**, so it uses the existing `claude` login — no API key, no separate billing.
Multiple conversations live side by side, each backed by its own Claude Code session.

```
SUPER + A                 toggle the panel (modules/hyprland.nix)
Enter                     send
Shift + Enter             newline
Escape                    close (every conversation is kept)
```

## Conversations

The left sidebar lists every conversation, most recently used first.

- **New chat** starts a fresh thread. If the current one is still empty it is reused rather
  than stacking up empties.
- **Click** a row to switch to it. The next turn resumes *that* thread's session, so the
  threads stay independent.
- **Right-click** a row for **Rename** / **Delete**. Titles default to the first thing you
  asked.
- The sidebar toggle in the header collapses it when the full width is wanted for reading.
- A turn keeps streaming into its own conversation while you read or type in another one; the
  row is marked with `*` and the status line says which thread is answering.

Everything is stored in `conversations.json` in the plugin data dir
(`~/.local/state/noctalia/plugins/data/tklas/claude_chat/`), so the list, the transcripts and
the session ids survive a shell restart. 40 conversations and 60 messages per conversation are
kept; the oldest fall off. A `history.json` from v1.0 of this plugin is migrated on first run.

## How it works

Each turn writes the prompt to a file under the plugin data dir and streams

```sh
cat <prompt> | claude -p --output-format stream-json --include-partial-messages --verbose ...
```

through `noctalia.runStream`. Text deltas are appended to the open assistant bubble as they
arrive (plain text while streaming, re-rendered as markdown when the turn ends). The
`session_id` the CLI reports is stored on the conversation and passed as `--resume` on its next
turn.

## Entries

| Entry | Id | What it is |
|-------|----|------------|
| Panel | `tklas/claude_chat:chat` | The chat window. `noctalia msg panel-toggle tklas/claude_chat:chat` |
| Bar widget | `tklas/claude_chat:toggle` | Opens the panel; shows a spinner glyph while a turn is streaming |

Both are driveable over IPC:

```sh
noctalia msg panel-open tklas/claude_chat:chat "prefilled prompt"   # opens with the composer filled in
noctalia msg plugin tklas/claude_chat:chat all ask "what is my IP?" # ask in the active conversation
noctalia msg plugin tklas/claude_chat:chat all new                 # start a new conversation
noctalia msg plugin tklas/claude_chat:chat all switch c3           # switch by conversation id
noctalia msg plugin tklas/claude_chat:chat all stop                # detach from the running turn
```

## Settings

Settings → Plugins → gear on the Claude Chat row.

| Setting | Default | Notes |
|---------|---------|-------|
| Model | account default | `opus` / `sonnet` / `haiku` map to `--model` |
| Capabilities | chat only | `chat` = `--restricted --tools ''`; `read_only` = Read/Glob/Grep/WebSearch; `agent` = `--permission-mode bypassPermissions` |
| Working directory | `~` | cwd of the `claude` process; decides project context and `CLAUDE.md` outside chat-only mode |
| Extra system prompt | empty | `--append-system-prompt` |
| claude executable | `claude` | absolute path if it is not on Noctalia's PATH |

**Agent mode skips every permission prompt** — Claude can edit files and run commands in the
working directory without asking. Chat-only mode is the default for a reason.

## Development

The plugin directory is symlinked into `~/.local/share/noctalia/plugins/` from the nixos repo
(`modules/noctalia-claude-chat.nix`, via `mkOutOfStoreSymlink`), so editing a `.luau` file here
hot-reloads it in the running shell — no rebuild. Manifest changes need a reload:

```sh
noctalia plugins lint .            # validate plugin.toml against the scripts
noctalia msg plugins disable tklas/claude_chat && noctalia msg plugins enable tklas/claude_chat
```

`plugin_api = 28` is required for `panel.openContextMenu` (the right-click menu); Noctalia 5.1
supports up to 32.

## Known limits

- **Stop detaches, it does not kill.** `noctalia.runStream` hands back no process handle, so
  Stop stops consuming output; the `claude` process finishes on its own.
- A turn that produces no output for 3 minutes is failed by a watchdog on the panel's tick.
- One turn at a time, across all conversations.

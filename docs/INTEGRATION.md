# Codex integration notes

## Capability decision

Coralline Codex uses two supported Codex surfaces and one local companion:

- `tui.status_line` and `/statusline` provide Codex-owned live fields such as
  model/reasoning, context, limits, and token totals.
- Custom `.tmTheme` files under `$CODEX_HOME/themes` color the native footer.
- The authenticated app-server provides `account/rateLimits/read` and, when
  available, `account/usage/read` for exact account snapshots.
- On Bash companion platforms, a private tmux server renders additional local
  fields without altering the user's tmux server or configuration.

Codex does not document a command-valued external `statusLine` or
`subagentStatusLine` renderer equivalent to Claude Code. Hooks are lifecycle
callbacks, not a continuous footer renderer. Patching the Codex binary was
rejected because it would be brittle and unsafe to distribute.

## Native invocation

The launcher supplies per-invocation overrides equivalent to:

```toml
tui.status_line = [
  "model-with-reasoning",
  "context-remaining",
  "five-hour-limit",
  "weekly-limit",
  "used-tokens",
]
tui.status_line_use_colors = true
tui.theme = "coralline-claude-coral"
```

These values are CLI overrides. The installers never rewrite Codex's
`config.toml`.

## Bash companion lifecycle

On Linux, macOS, WSL, and compatible Git Bash environments, the wrapper creates
a private tmux server with `tmux -L coralline-<pid> -f /dev/null`. Its status
command runs `lib/render.sh` once per second. Arguments remain a Bash array and
the mode-0700 temporary launcher uses `%q`; no user argument is evaluated as
shell source. Traps stop the watcher, private server, and temporary directory.

The watcher uses the authenticated Codex app-server for plan limits and tails
only `token_count` events from the active local rollout. It handles partial
JSONL records, detects session rollover, and atomically writes mode-0600 cache
files. Rendering performs no network request.

Transient account failures keep the most recent valid snapshot and record an
error/attempt time. The renderer marks snapshots stale after the configured
threshold. Quota projection history contains only `[timestamp, usedPercent]`
samples, is keyed by window duration and reset epoch, and is pruned after 14
days.

## Native Windows lifecycle

`install.ps1` installs the same generated native themes, a PowerShell launcher,
and a command shim. With `-ShellHook`, it writes a marked and reversible block
to the current-user PowerShell profile defining `codex` and
`coralline-codex` functions. The original profile is backed up before a change.

Native Windows applies the Codex footer/theme overrides and supports exact
`coralline-codex usage`. It intentionally does not claim the separate tmux
companion. WSL is the supported full-companion Windows tier.

## Availability and graceful degradation

| Segment | Source | When unavailable |
|---|---|---|
| native model/reasoning/context | Codex session | omitted by Codex |
| native tokens/limits | Codex account/session state | omitted by Codex |
| companion plan limits | `account/rateLimits/read` | hidden; last valid snapshot retained on transient failure |
| burn projection | private local percentage history | labeled warming/idle or hidden |
| companion session tokens | active rollout `token_count` events | hidden until the first event |
| cwd/repository/Git | local filesystem and Git | repository/Git hidden outside a repo |
| Node/Python | pin/environment; optional subprocess | hidden |
| companion model/profile | launch-time layered configuration | `auto`/`default` label |
| elapsed/clock | local process clock | always available |

The native footer is authoritative for changes made later with `/model`.
Coralline never fabricates unavailable values.

## Files and reversible changes

Bash-family installation owns:

- `$CODEX_HOME/coralline-codex/`
- `$CODEX_HOME/coralline-codex.conf`
- `$CODEX_HOME/coralline-codex-cache/`
- `$CODEX_HOME/themes/coralline-*.tmTheme`
- `${CORALLINE_BIN_DIR:-$HOME/.local/bin}/coralline-codex`
- an optional marked block in the selected Bash/Zsh rc file

Native PowerShell uses `coralline-codex.windows.json`, a `.cmd` shim, and an
optional marked profile block. Both installers refuse unrelated command paths,
back up replaced material, preserve user configuration on update, and remove
only recorded managed hooks on uninstall.

## Sources used for the design

- [Official Codex app-server protocol](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md#auth-endpoints)
- [Official Codex CLI features and slash commands](https://learn.chatgpt.com/docs/codex/cli/features)
- [Official Codex configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference)
- [`wakamex/codex-cli-usage`](https://github.com/wakamex/codex-cli-usage), an
  independent implementation using `account/rateLimits/read`

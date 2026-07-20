# Codex integration notes

## Capability decision

The implementation was selected against the current Codex manual and the local
Codex CLI 0.144.6 installation.

Documented/verified surfaces:

- [`tui.status_line`](https://learn.chatgpt.com/docs/config-file/config-reference)
  is an ordered native footer field list; `/statusline` configures it
  interactively.
- Native items include model/reasoning, directory/project, Git branch, context,
  5-hour and weekly limits, token totals, session identity, permissions, and
  run state. Availability is field-specific.
- `tui.status_line_use_colors` derives footer colors from the active syntax
  theme, and custom `.tmTheme` files live under `$CODEX_HOME/themes`.
- [Codex hooks](https://learn.chatgpt.com/docs/hooks) are lifecycle callbacks,
  not a continuous status renderer. They require trust and do not provide a
  supported way to replace the footer.
- Notifications report lifecycle events; plugins bundle Codex capabilities but
  do not add arbitrary TUI footer segment renderers.

There is no documented Codex equivalent of Claude Code's command-valued
`statusLine` or `subagentStatusLine`. Patching the Codex binary was rejected.

## Exact mechanism

`coralline-codex` starts Codex with per-invocation overrides:

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

These are CLI overrides, not edits to `config.toml`. The wrapper then creates a
private tmux server (`tmux -L coralline-<pid> -f /dev/null`) with one status
command. The command runs `lib/render.sh` every second. The private server
neither reads nor alters the user's tmux configuration.

Arguments are retained as a Bash array and written with `%q` into a mode-0700
temporary launcher. Paths are consistently quoted. Temporary files are removed
on exit.

## Availability and graceful degradation

| Segment | Source | Behavior when unavailable |
|---|---|---|
| native model/reasoning | Codex session | omitted by Codex |
| native context/tokens/limits | Codex API/session state | omitted by Codex |
| cwd/repository/Git | local filesystem and Git | repository/Git hidden outside a repo |
| Node | pin file; optional local subprocess | hidden |
| Python | environment/pin file; optional local subprocess | hidden |
| companion model/profile | CLI arguments and layered TOML at launch | `auto`/`default` label |
| elapsed/clock | local process clock | always available |

The wrapper cannot observe a later in-session `/model` selection. The native
footer remains authoritative and updates correctly; the companion explicitly
represents launch-time resolution. No live values are fabricated.

## Files and configuration safety

Installed files are confined to:

- `$CODEX_HOME/coralline-codex/`
- `$CODEX_HOME/coralline-codex.conf`
- `$CODEX_HOME/themes/coralline-*.tmTheme`
- `${CORALLINE_BIN_DIR:-$HOME/.local/bin}/coralline-codex` (symlink)

The installer refuses to overwrite an unrelated command path. Updates back up
every replaced installed tree and theme. Configuration changes back up the
companion config before writing it. Uninstall moves material files into a
recoverable backup. `$CODEX_HOME/config.toml` and profile files remain unchanged.

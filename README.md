# Coralline Codex

Coralline Codex is a Coralline-inspired status experience for the OpenAI Codex
CLI. It combines Codex's documented native footer with an isolated tmux
companion that keeps the Powerlevel10k-style rendering, plan-limit tracking,
session tokens, themes, Git detail, elapsed time, clock, and optional
Node/Python segments.

This is an independent Codex port of
[Nanako0129/coralline](https://github.com/Nanako0129/coralline), not the
upstream Claude Code project. MIT attribution and port details are in
[NOTICE.md](NOTICE.md).

[繁體中文安裝說明](README.zh-TW.md) · [Integration details](docs/INTEGRATION.md)

```text
 ~/work/coralline-codex   ⬢ coralline-codex    main !2 ?1 ↑1   model gpt-5.6   profile default   ⧖ 12m08s   ◷ 19:42 
```

## Why the integration is hybrid

Codex CLI 0.144.6 has a native configurable status line (`/statusline` and
`tui.status_line`). It provides live model/reasoning, context, usage limits,
tokens, Git branch, and session state. Codex does not expose Claude Code's
external `statusLine`/`subagentStatusLine` command-renderer API, and its native
footer does not accept arbitrary Node or Python segments.

Coralline Codex therefore uses each interface only for what it reliably knows:

| Surface | Reliable fields |
|---|---|
| Codex native footer | live model + effort, context remaining, 5-hour/weekly limits, session tokens |
| isolated tmux companion | working directory, repository, detailed Git state, plan-limit remaining/reset, session input/output/total tokens, optional Node/Python, launch model/profile, elapsed time, clock |

The companion starts a private tmux server and does not read or change your
normal tmux configuration. A separate background watcher asks Codex's official
app-server for account limits and watches the active local rollout for session
tokens. It writes mode-0600 caches; the renderer only reads those caches and
makes zero network requests. If tmux is unavailable or the process is not
interactive, the wrapper falls back to the themed native Codex footer.

## Requirements

- Linux or macOS with Bash 4+
- Python 3.8+ (standard library only)
- Git and the Codex CLI
- tmux for the live Powerlevel10k companion bar
- a Nerd Font for icons, or the built-in ASCII fallback

`jq` is not required.

## Install

Clone and inspect the repository, then run the local installer:

```bash
git clone https://github.com/waynehacking8/coralline-codex.git
cd coralline-codex
./install.sh
~/.local/bin/coralline-codex verify
```

Add `~/.local/bin` to `PATH` if it is not already present. Custom locations are
supported safely, including spaces:

```bash
CODEX_HOME="$HOME/Library/Application Support/codex" \
CORALLINE_BIN_DIR="$HOME/bin with spaces" \
./install.sh
```

The documented primary method is a local, reviewable checkout. There is no
`curl | bash` installation path.

## Use

Launch Codex through the wrapper:

```bash
coralline-codex
coralline-codex --model gpt-5.6 --profile work
coralline-codex --no-companion
```

All unrecognized arguments are passed to Codex without string evaluation. For
non-interactive subcommands such as `exec`, the wrapper uses the native settings
and skips tmux automatically.

Preview every theme:

```bash
coralline-codex preview
```

Fetch the exact current plan snapshot and reset time on demand:

```bash
coralline-codex usage
```

## Configure

Run the interactive wizard:

```bash
coralline-codex configure
```

Or make focused changes:

```bash
coralline-codex configure --theme catppuccin-mocha --style pill
coralline-codex configure --node on --python on --runtime-probe off
coralline-codex configure --ascii on
coralline-codex configure --usage-refresh 60
coralline-codex configure --show
```

Node checks `.nvmrc` and `.node-version`; Python checks `VIRTUAL_ENV`, conda,
and `.python-version`. `--runtime-probe on` additionally runs `node --version`
or `python3 --version` when no pinned/environment value exists. Missing data
hides only that segment.

The default `limits` and `tokens` segments render compact values such as
`7d ▰▰▰▰▱ 88% ↺6d21h` and `Σ10.4M ↑10.3M ↓70.5k`. Account limits refresh in a
background process every 60 seconds by default (minimum 30 seconds). Rendering
itself remains local and network-free.

Themes: `claude-coral`, `catppuccin-mocha`, `dracula`, `gruvbox-dark`,
`lunar-pink`, `mono`, `nord`, `reverie`, and `tokyo-night`.

## Update

From a checkout, review and fast-forward it before reinstalling:

```bash
git pull --ff-only
./install.sh --update
coralline-codex verify
```

The installed command also supports a Git-based update (never a remote shell
pipe):

```bash
coralline-codex update
```

Existing runtime files and generated themes are saved under
`$CODEX_HOME/coralline-codex-backups/<timestamp>/` before replacement. The
companion config is preserved on update.

## Uninstall

```bash
coralline-codex uninstall
```

The installed runtime, generated themes, and companion config are moved to a
timestamped recoverable backup. The command symlink is removed only when it
still points to this installation. `config.toml` is never edited.

## Verify and test

```bash
coralline-codex verify
./test/run.sh
```

The suite covers themed rendering, width constraints, clean/dirty/detached Git,
missing optional data, configuration merge preservation, paths with spaces,
fresh install, upgrade, and uninstall.

## Usage data and limitations

- Plan windows come from Codex's documented `account/rateLimits/read`
  app-server method. Labels are classified by the returned window duration, so
  a weekly-only account is shown correctly even when it is the primary window.
- Session token totals come from the active rollout's `token_count` events.
  Missing or not-yet-emitted events hide the segment instead of showing zero.
- The native footer remains authoritative for live context-window percentage,
  model, and reasoning effort.
- The companion's model/profile describe launch-time resolution. If `/model`
  changes the model during a session, the native footer updates but the
  companion launch segment does not.
- Codex exposes no supported custom renderer for native footer values or
  subagent rows. They therefore cannot receive Coralline pill backgrounds.
- No network request occurs in `render.sh`. The separate usage watcher invokes
  the authenticated Codex app-server at the configured refresh interval;
  `coralline-codex update` and Codex itself can also use the network.

## License

MIT. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).

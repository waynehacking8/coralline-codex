# Coralline Codex

> A [Powerlevel10k](https://github.com/romkatv/powerlevel10k)-inspired status
> experience for the OpenAI Codex CLI, pairing Codex's native footer with a live
> terminal companion for usage limits, context, session tokens, and active
> Codex subagents.

[繁體中文說明](./README.zh-TW.md)

![Six Coralline Codex themes with connected Powerline bars and active agent rows](./assets/hero.svg)

## What you get

```text
agent: scout [explorer] | Explore config sources | model gpt-5.4 high | context 21% 42.0k | elapsed 2m05s
bar:   7d 79% reset 1d11h | tokens 123.4k | context 21% | ~/dev/coralline-codex | git main+!? | 16:53
```

The README preview uses portable ASCII labels so it renders consistently on
GitHub. The live terminal uses the selected Powerline or ASCII style.

| Segment | Shows |
|---|---|
| `limits` | exact plan remaining percentage, a five-cell gauge, local reset countdown, and stale-data warning |
| `burn` | conservative time-to-exhaustion projection with warming, idle, reset-safe, and tracking states |
| `tokens` | active-session input, output, and total token counts |
| `context` | current context-window use, percentage, and a five-cell gauge |
| `dir` | current directory with long-path collapsing |
| `project` | repository name; hidden outside a Git repository |
| `git` | branch, staged `+`, modified `!`, untracked `?`, ahead `↑`, and behind `↓` state |
| `stash` | Git stash count; hidden when zero |
| `node` / `python` | pinned or active runtime environment; opt-in and hidden when undetected |
| `model` / `reasoning` / `profile` | live session model and reasoning effort (launch-time until the first turn lands), and the launch-time profile |
| `elapsed` | session wall-clock duration |
| `clock` | local 24-hour time |

The native Codex footer remains authoritative for live model, reasoning effort,
context remaining, limits, and used tokens. The companion adds the fields Codex
does not render there and progressively compacts down to a 30-column terminal.
Gauges and projections change color with urgency. The native field list is
configurable and can also be left entirely to the user's Codex configuration.

While Codex subagents are running, the Bash companion expands from one row up
to five total tmux status rows. Each agent row can show its Codex nickname,
role, spawn task, effective model and reasoning effort, exact token/context
usage, elapsed turn time, and nested-agent count. Rows collapse as soon as work
completes; Codex's native `/agent` or `/subagents` view remains the history and
navigation surface.

Coralline Codex includes nine native Codex themes, four companion styles, an
ASCII fallback, a guided visual setup, and an optional managed shell hook so
ordinary commands such as `codex --yolo` launch through Coralline automatically.

This is an independent Codex port of
[Nanako0129/coralline](https://github.com/Nanako0129/coralline), not the upstream
Claude Code project. Attribution and port details are in [NOTICE.md](./NOTICE.md).

## Platform support

| Platform | Support tier | Experience |
|---|---|---|
| Linux, Bash 4+ | Full | Native Codex footer + live isolated tmux companion |
| macOS, Homebrew Bash 4+ | Full | Native Codex footer + live isolated tmux companion |
| Windows 11 with WSL2 | Full | Same Linux companion experience inside WSL |
| Native Windows PowerShell | Native | Themed Codex footer, limits/tokens, exact `usage`, managed PowerShell hook |
| Windows Git Bash/MSYS2 | Compatible | Bash lifecycle and fallback tested; full companion requires a working tmux |

Native Windows does not show the extra Powerlevel10k companion or agent rows
because Codex does not expose an external footer renderer there. It still gets
the configurable native Codex fields, Codex's native `/agent` view, and
on-demand usage tracking. Use WSL2 for feature parity with Linux and macOS.

## Install

The supported installation path is a local, reviewable checkout. The project
does not ask you to pipe a remote script into a shell.

### Linux

Install Bash 4+, Python 3.8+, Git, Codex CLI 0.144.6+, and tmux with your package manager,
then:

```bash
git clone https://github.com/waynehacking8/coralline-codex.git
cd coralline-codex
./install.sh --shell-hook auto
~/.local/bin/coralline-codex verify
```

Open a new shell. Normal `codex` commands now use Coralline. If
`~/.local/bin` is not on `PATH`, add it to your shell configuration for direct
`coralline-codex` commands.

### macOS

macOS ships an older Bash, so install current dependencies and Codex CLI
0.144.6+ first:

```bash
brew install bash python tmux git
git clone https://github.com/waynehacking8/coralline-codex.git
cd coralline-codex
./install.sh --shell-hook zsh
~/.local/bin/coralline-codex verify
```

The launcher uses the Homebrew Bash found on `PATH`. The managed hook is added
to `~/.zshrc`; open a new terminal or source that file once.

### Windows 11 + WSL2

Clone and run the Linux instructions inside WSL. Install `tmux`, Python 3, Git,
and Bash in that distribution. This is the full Windows experience.

### Native Windows PowerShell

Install Git, Python 3.8+, and Codex CLI 0.144.6+, then run from PowerShell:

```powershell
git clone https://github.com/waynehacking8/coralline-codex.git
Set-Location coralline-codex
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -ShellHook
. $PROFILE.CurrentUserAllHosts
codex --yolo
coralline-codex usage
```

The optional hook adds managed `codex` and `coralline-codex` functions to the
current-user PowerShell profile. The installer also creates
`$HOME\.local\bin\coralline-codex.cmd` without silently changing `PATH`.

Custom locations, including paths with spaces, are supported on every tier.

## Use

```bash
codex --yolo                         # when the optional shell hook is installed
coralline-codex                     # direct wrapper launch
coralline-codex --model gpt-5.6
coralline-codex --no-companion      # native footer only
coralline-codex usage               # refresh and print exact account usage
coralline-codex preview             # preview all themes (Bash companion tier)
```

Arguments are passed as an array without string evaluation. Non-interactive
Codex subcommands such as `exec` skip tmux automatically. Coralline does not
change the meaning or security implications of `--yolo`; it simply forwards the
flag.

To bypass an installed hook for one command:

```bash
CORALLINE_CODEX_DISABLE=1 codex --version
```

```powershell
$env:CORALLINE_CODEX_DISABLE = '1'; codex --version; Remove-Item Env:CORALLINE_CODEX_DISABLE
```

## Configure

The Bash companion tier has a visual wizard:

```bash
coralline-codex configure
```

Or make focused changes:

```bash
coralline-codex configure --theme catppuccin-mocha --style powerline
coralline-codex configure --node on --python on --runtime-probe off
coralline-codex configure --segments "limits burn tokens context dir git elapsed clock"
coralline-codex configure --agents on --agent-rows 3
coralline-codex configure --native-fields "model-with-reasoning run-state context-remaining task-progress"
coralline-codex configure --native-fields inherit  # preserve config.toml's field list
coralline-codex configure --ascii on --usage-refresh 60
coralline-codex configure --preview
```

Native PowerShell supports theme/native-footer configuration:

```powershell
coralline-codex configure --theme nord
coralline-codex configure --native-fields "model-with-reasoning,run-state,task-progress"
coralline-codex configure --show
```

Runtime probes are off by default. Node checks `.nvmrc` and `.node-version`;
Python checks virtualenv, conda, and `.python-version`. Missing data hides only
that segment. The renderer progressively compacts limits and tokens down to a
30-column terminal instead of dropping the critical values first.

## How usage tracking works

The background watcher asks the authenticated Codex app-server for account
limits and tails Codex's local rollout protocol for session and subagent state,
then writes atomic mode-0600 caches under
`$CODEX_HOME/coralline-codex-cache/`. Rendering is local and network-free.
Transient failures preserve the last valid values and visibly mark them stale.

Subagent task labels and telemetry live only in the private mode-0700 launch
directory and are removed when the companion exits. Projection history contains
only timestamps and percentage-used samples. It is
stored mode 0600, separated by reset window, pruned after 14 days, and never
uploaded by Coralline. A projection is explicitly labeled as warming up until a
sufficient baseline exists; it is an estimate, not a promise from OpenAI.

The native Codex footer remains authoritative for live context percentage,
model, and reasoning effort. The companion model and reasoning labels follow
in-session `/model` switches within a couple of seconds by reading the session
rollout. The one blind window is a switch made before the first message of a
fresh session: Codex only creates the rollout on the first turn, so the
companion shows the launch-time value until the first response starts, then
catches up on its own.

See [Codex feature coverage](docs/CODEX-COVERAGE.md) for the supported-field
matrix, deliberate exclusions, and related Codex status projects surveyed.

## Update and uninstall

From a checkout:

```bash
git pull --ff-only
./install.sh --update --shell-hook auto
coralline-codex verify
```

On native Windows, pull the checkout and run `./install.ps1 -Update`; an existing
managed profile hook is preserved. Updates print the version transition and
release highlights.

```bash
coralline-codex uninstall
```

The installed runtime, generated themes, companion config, and managed hook are
removed only within their recorded scope. Material files are moved to a
timestamped recoverable backup. Coralline never edits Codex's `config.toml`.

## Verify and contribute

```bash
coralline-codex verify
./test/run.sh
python3 tools/render_assets.py --check
```

CI exercises Linux, macOS, native Windows PowerShell, and Windows Git Bash. See
[CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and the complete
[quality gates](docs/QUALITY-GATES.md) before sharing changes.

## License

MIT. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).

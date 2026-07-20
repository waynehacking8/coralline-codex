# Contributing

Thank you for improving Coralline Codex. Keep changes small, reviewable, and
portable across Linux, macOS, WSL, native PowerShell, and Git Bash where the
feature applies.

## Development setup

Required: Bash 4+, Python 3.8+, Git, and ShellCheck. tmux enables the interactive
companion lifecycle test. PowerShell 7 is needed for the native Windows suite.

```bash
git clone https://github.com/waynehacking8/coralline-codex.git
cd coralline-codex
./test/run.sh
```

Before opening a pull request, run the checks in
[docs/QUALITY-GATES.md](docs/QUALITY-GATES.md). If palette data changes, rebuild
and commit the deterministic visuals:

```bash
python3 tools/render_assets.py
python3 tools/render_assets.py --check
```

## Design constraints

- Do not patch the Codex binary or depend on undocumented credential files.
- Keep rendering network-free; network/account work belongs in the watcher.
- Never fabricate live values. Hide unavailable fields or mark stale/estimated
  values explicitly.
- Do not edit Codex `config.toml`; use scoped CLI overrides.
- Preserve unrelated shell/profile content and back it up before managed edits.
- Avoid new runtime dependencies unless the benefit clearly outweighs the
  portability cost.

Bug reports should include the OS, shell, Bash/Python/Codex versions, whether
tmux is installed, and sanitized output from `coralline-codex verify`. Never
attach Codex auth files or complete rollout logs.


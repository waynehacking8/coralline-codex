# Changelog

## 0.3.1 - 2026-07-22

- Write the managed shell hook with the Codex binary path as given instead of
  resolving symlinks, so a version-managed install (such as the standalone
  `current` link) keeps launching the latest Codex after self-updates rather
  than pinning the hook to one release path and re-triggering the update
  prompt on every launch.

## 0.3.0 - 2026-07-21

- Add dynamic Codex subagent rows with nickname, role, task, effective model and
  reasoning, exact context/token usage, elapsed time, nesting, overflow, and
  immediate completion collapse.
- Add configurable coverage for every current Codex native status-line field,
  including an `inherit` mode that preserves the user's own field list.
- Add companion context, reasoning-effort, and Git stash segments.
- Keep transparency and terminal-compositor effects out of scope so the project
  remains focused on reliable Codex bar support.

## 0.2.1 - 2026-07-21

- Add a connected Powerline-arrow style and make it the default for new installs,
  while retaining pill, lean, classic, and ASCII rendering.
- Rebuild the README opening and theme sampler to follow the upstream
  Coralline layout and aesthetic with the connected arrow treatment.

## 0.2.0 - 2026-07-20

- Add a guided visual setup with live previews, three layouts, three rendering
  styles, font compatibility selection, and strict validation.
- Add conservative quota burn-rate projections backed by private local history,
  explicit warming/idle/reset-safe states, and adaptive 30-column rendering.
- Add managed, reversible Bash and Zsh hooks so normal commands such as
  `codex --yolo` can launch through Coralline automatically.
- Add a native Windows PowerShell installer, launcher, configuration command,
  optional managed profile hook, exact on-demand account usage, and safe
  uninstall. Document WSL as the full Windows companion tier.
- Harden usage caches with atomic writes, permission enforcement, freshness and
  failure metadata, incremental rollout reads, and session rollover detection.
- Show version transitions and release highlights after updates.
- Add reproducible README visuals and hosted Linux, macOS, native Windows, and
  Windows Git Bash CI coverage.

## 0.1.1 - 2026-07-20

- Add plan-limit remaining percentage and reset countdown to the companion bar.
- Add live per-session input, output, and total token counters.
- Fetch limits through Codex's official authenticated app-server and keep
  rendering network-free through mode-0600 caches.
- Add `coralline-codex usage` for an exact on-demand account snapshot.
- Correctly classify weekly-only plans by window duration.

## 0.1.0 - 2026-07-20

- Initial Codex port.
- Native Codex footer integration with generated Coralline `.tmTheme` files.
- Isolated tmux Powerlevel10k companion with nine themes and ASCII fallback.
- Optional Node and Python segments with conservative detection.
- Safe install, configure, update, uninstall, and verification commands.
- English and Traditional Chinese documentation.

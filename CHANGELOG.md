# Changelog

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

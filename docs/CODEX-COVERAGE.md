# Codex feature coverage

Coralline Codex implements status information only when Codex or the local
workspace provides an authoritative source. It does not infer private billing,
scrape terminal pixels, or patch the Codex binary.

## Native Codex footer

`CC_NATIVE_FIELDS` accepts every status-line item supported by Codex CLI 0.144.6:

```text
model model-name model-with-reasoning reasoning current-dir project-name
project-root git-branch pull-request-number branch-changes run-state status
permissions approval-mode approval context-remaining context-used context-usage
five-hour-limit weekly-limit codex-version context-window-size used-tokens
total-input-tokens total-output-tokens thread-id session-id fast-mode raw-output
thread-title workspace-headline task-progress
```

Aliases are preserved because Codex itself accepts them. `inherit` omits the
scoped `tui.status_line` override while retaining the selected Coralline theme
and status colors.

## Companion and subagent coverage

| Capability | Source | Coverage |
|---|---|---|
| plan windows and resets | authenticated Codex app-server | exact snapshot, stale/failure handling |
| burn projection | private percentage history | conservative estimate, clearly labeled |
| root tokens and context | rollout `token_count` | exact when Codex emits it |
| agent tree | `session_meta.parent_thread_id` and agent path | direct and nested descendants |
| agent identity | nickname, role, path, spawn event | exact when present |
| agent task | spawn prompt or addressed inter-agent message | whitespace-normalized and locally truncated |
| agent model/reasoning | spawn event and `turn_context` | effective values |
| agent lifecycle | task and collab status events | active rows; completed rows collapse |
| agent tokens/context | each child rollout's `token_count` | independent exact counters and gauge |
| Git/workspace/runtime | local filesystem and tools | hidden rather than guessed |

Codex does not currently expose a documented command-valued `statusLine` or
`subagentStatusLine`. Coralline therefore renders the companion in an isolated
tmux status area. It does not inject rows inside Codex's prompt region. Native
Windows retains Codex's built-in `/agent` view but needs WSL for companion rows.

## Deliberate exclusions

| Upstream-style field | Reason |
|---|---|
| exact session cost | ChatGPT-backed Codex sessions do not expose an authoritative per-session currency total |
| exact agent edit-line totals | Codex rollout events do not identify a reliable per-agent added/removed aggregate |
| terminal transparency or blur | controlled by terminal compositor settings, not the Codex status protocol |
| output-style/personality label | not consistently exposed as live status telemetry across supported Codex versions |

## Related projects surveyed

- [codex-hud](https://github.com/fwyc0573/codex-hud) is the closest external
  tmux HUD and demonstrates multi-session and subagent activity monitoring.
- [oh-my-codex](https://github.com/Yeachan-Heo/oh-my-codex) combines Codex's
  native footer with a separate orchestration HUD.
- [token-tracker](https://github.com/stormzhang/token-tracker) uses hooks to
  append status summaries rather than maintaining a persistent native footer.
- [abtop](https://github.com/graykode/abtop) is an external terminal monitor
  for coding-agent sessions and usage.
- [CodexBar](https://github.com/steipete/CodexBar) is a macOS menu-bar usage
  monitor rather than an in-terminal status line.
- [codex-cli-usage](https://github.com/wakamex/codex-cli-usage) uses the Codex
  app-server for rate-limit snapshots.
- [tmux-agent-status](https://github.com/samleeney/tmux-agent-status) tracks
  high-level working/done state across tmux sessions.

Coralline's distinct focus is a compact, themeable Powerline bar that combines
the current native Codex footer surface with authoritative local subagent rows.

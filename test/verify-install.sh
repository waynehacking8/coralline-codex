#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
CODEX_DIR=${CODEX_HOME:-$HOME/.codex}
while (($#)); do
  case $1 in
    --codex-home) shift; CODEX_DIR=${1:?missing path} ;;
    *) printf 'verify: unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

fail=0
check() { if "$@"; then printf 'ok  %s\n' "$*"; else printf 'FAIL %s\n' "$*" >&2; fail=1; fi; }
check test -x "$ROOT/bin/coralline-codex"
check test -x "$ROOT/lib/render.sh"
check test -x "$ROOT/lib/shell_integration.py"
check test -x "$ROOT/lib/usage.py"
check test -f "$CODEX_DIR/coralline-codex.conf"
check test -f "$CODEX_DIR/themes/coralline-claude-coral.tmTheme"
check bash -n "$ROOT/bin/coralline-codex"
check bash -n "$ROOT/lib/render.sh"
check python3 -c 'import pathlib,sys; [compile(pathlib.Path(p).read_text(), p, "exec") for p in sys.argv[1:]]' \
  "$ROOT/lib/config.py" "$ROOT/lib/shell_integration.py" "$ROOT/lib/usage.py" "$ROOT/tools/generate_themes.py"
check "$ROOT/lib/render.sh" --plain --width 120 --cwd "$PWD"
check env CODEX_HOME="$CODEX_DIR" codex --strict-config \
  -c 'tui.status_line=["model-with-reasoning","run-state","context-remaining","five-hour-limit","weekly-limit","used-tokens","fast-mode","task-progress"]' \
  -c tui.status_line_use_colors=true -c 'tui.theme="coralline-claude-coral"' --version
((fail == 0)) || exit 1
printf 'Verification passed. No network request was made by the renderer.\n'

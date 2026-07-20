#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
CODEX_DIR=${CODEX_HOME:-$HOME/.codex}
CONFIG=${CORALLINE_CODEX_CONFIG:-$CODEX_DIR/coralline-codex.conf}
BACKUPS=$CODEX_DIR/coralline-codex-backups
declare -a CHANGES=() THEMES=()
SHOW=0 PREVIEW=0 WIZARD=0 SHELL_REQUEST=preserve

usage() {
  cat <<'EOF'
usage: configure.sh [options]
  --wizard               open the guided visual setup
  --preview              preview the effective companion configuration
  --theme NAME            select one of the bundled themes
  --style powerline|pill|lean|classic
                          select connected arrows, rounded pills, a lean line, or square blocks
  --ascii auto|on|off     force or disable the ASCII fallback
  --node on|off           show Node when an environment/version is detected
  --python on|off         show Python when an environment/version is detected
  --runtime-probe on|off  allow node/python3 subprocess probes
  --segments "..."        set companion segment priority/order
  --usage-refresh SECS    refresh plan-limit cache interval (minimum 30)
  --usage-stale SECS      mark cached limits stale after this age (minimum 60)
  --shell-hook on|off     install or remove the managed codex shell function
  --show                  print the effective companion configuration
EOF
}

while IFS=$'\t' read -r theme _; do
  [[ $theme == \#* || -z $theme ]] && continue
  THEMES+=("$theme")
done < "$ROOT/themes/palettes.tsv"

theme_exists() {
  local wanted=$1 item
  for item in "${THEMES[@]}"; do [ "$item" = "$wanted" ] && return 0; done
  return 1
}

segments_valid() {
  local item
  for item in $1; do
    case $item in
      limits | burn | tokens | dir | project | git | node | python | model | profile | elapsed | clock) ;;
      *) printf 'unknown segment: %s\n' "$item" >&2; return 1 ;;
    esac
  done
}

render_preview() {
  local theme=$1 style=$2 ascii=$3 segments=$4 width=${5:-120} now
  now=$(date +%s)
  CC_THEME=$theme CC_STYLE=$style CC_ASCII=$ascii CC_SEGMENTS="$segments" \
    CC_NODE=off CC_PYTHON=off CORALLINE_RATE_AVAILABLE=1 CORALLINE_LIMIT_COUNT=1 \
    CORALLINE_LIMIT1_LABEL=7d CORALLINE_LIMIT1_USED=15 CORALLINE_LIMIT1_REMAINING=85 \
    CORALLINE_LIMIT1_RESET=$((now + 597600)) CORALLINE_RATE_UPDATED=$now \
    CORALLINE_LIMIT1_BURN_STATE=tracking CORALLINE_LIMIT1_BURN_ETA=302400 \
    CORALLINE_SESSION_AVAILABLE=1 CORALLINE_SESSION_TOTAL=12463 \
    CORALLINE_SESSION_INPUT=12456 CORALLINE_SESSION_OUTPUT=7 \
    CORALLINE_MODEL=gpt-5.6-codex CORALLINE_PROFILE=work CORALLINE_START_EPOCH=$((now - 754)) \
    CORALLINE_CODEX_CONFIG=/dev/null "$ROOT/lib/render.sh" --width "$width" --cwd "$ROOT"
}

load_current() {
  CC_THEME=claude-coral
  CC_STYLE=powerline
  CC_ASCII=auto
  CC_NODE=off
  CC_PYTHON=off
  CC_SEGMENTS='limits burn tokens dir git project node python model profile elapsed clock'
  CC_USAGE_REFRESH=60
  CC_USAGE_STALE_AFTER=180
  # User-selected companion configuration.
  # shellcheck disable=SC1090
  [ -f "$CONFIG" ] && . "$CONFIG"
}

resolve_theme_choice() {
  local choice=$1
  if [[ $choice =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#THEMES[@]})); then
    WIZARD_THEME=${THEMES[choice - 1]}
  elif [ -z "$choice" ]; then
    :
  elif theme_exists "$choice"; then
    WIZARD_THEME=$choice
  else
    printf 'Unknown theme: %s; keeping %s.\n' "$choice" "$WIZARD_THEME"
  fi
}

visual_wizard() {
  load_current
  local choice answer width
  WIZARD_THEME=$CC_THEME
  WIZARD_STYLE=$CC_STYLE
  WIZARD_ASCII=$CC_ASCII
  WIZARD_SEGMENTS=$CC_SEGMENTS
  WIZARD_NODE=$CC_NODE
  WIZARD_PYTHON=$CC_PYTHON
  WIZARD_REFRESH=$CC_USAGE_REFRESH
  WIZARD_STALE=$CC_USAGE_STALE_AFTER
  width=$(tput cols 2>/dev/null || printf 120)
  ((width > 140)) && width=140
  ((width < 60)) && width=60

  printf '\nCoralline Codex visual setup\n'
  printf 'Every choice is previewed locally; no account request is made.\n\n'
  printf 'Themes:\n'
  local index
  for index in "${!THEMES[@]}"; do
    printf '\n%2d) %s\n' "$((index + 1))" "${THEMES[$index]}"
    render_preview "${THEMES[$index]}" "$WIZARD_STYLE" "$WIZARD_ASCII" 'limits tokens dir git clock' "$width"
  done
  printf '\nTheme [%s]: ' "$WIZARD_THEME"; IFS= read -r choice
  resolve_theme_choice "$choice"

  printf '\nStyles:\n'
  for choice in powerline pill lean classic; do
    printf '%-10s ' "$choice"
    render_preview "$WIZARD_THEME" "$choice" "$WIZARD_ASCII" 'limits tokens dir git' "$width"
  done
  printf 'Style [%s]: ' "$WIZARD_STYLE"; IFS= read -r choice
  case $choice in '' ) ;; powerline | pill | lean | classic) WIZARD_STYLE=$choice ;; *) printf 'Unknown style; keeping %s.\n' "$WIZARD_STYLE" ;; esac

  printf 'Glyph mode: 1) automatic Nerd Font  2) ASCII [%s]: ' "$WIZARD_ASCII"; IFS= read -r choice
  case $choice in 1 | auto | '') ;; 2 | ascii) WIZARD_ASCII=on ;; *) printf 'Unknown glyph mode; keeping %s.\n' "$WIZARD_ASCII" ;; esac

  printf '\nSegment layouts:\n'
  printf '  1) Focused — quota, tokens, directory, Git, elapsed, clock\n'
  printf '  2) Full    — focused plus usage projection, project, runtimes, model, and profile\n'
  printf '  3) Minimal — quota, tokens, directory\n'
  printf '  4) Keep current custom order\n'
  printf 'Layout [4]: '; IFS= read -r choice
  case $choice in
    1) WIZARD_SEGMENTS='limits tokens dir git elapsed clock' ;;
    2) WIZARD_SEGMENTS='limits burn tokens dir git project node python model profile elapsed clock' ;;
    3) WIZARD_SEGMENTS='limits tokens dir' ;;
  esac
  if [[ " $WIZARD_SEGMENTS " == *' node '* ]]; then
    printf 'Show detected Node versions? [%s]: ' "$WIZARD_NODE"; IFS= read -r answer
    case $answer in y | Y | yes | on) WIZARD_NODE=on ;; n | N | no | off) WIZARD_NODE=off ;; esac
    printf 'Show detected Python environments? [%s]: ' "$WIZARD_PYTHON"; IFS= read -r answer
    case $answer in y | Y | yes | on) WIZARD_PYTHON=on ;; n | N | no | off) WIZARD_PYTHON=off ;; esac
  fi

  printf 'Quota refresh seconds [%s]: ' "$WIZARD_REFRESH"; IFS= read -r answer
  [[ $answer =~ ^[0-9]+$ ]] && ((answer >= 30)) && WIZARD_REFRESH=$answer
  printf 'Mark quota stale after seconds [%s]: ' "$WIZARD_STALE"; IFS= read -r answer
  [[ $answer =~ ^[0-9]+$ ]] && ((answer >= 60)) && WIZARD_STALE=$answer

  printf '\nFinal preview:\n'
  render_preview "$WIZARD_THEME" "$WIZARD_STYLE" "$WIZARD_ASCII" "$WIZARD_SEGMENTS" "$width"
  # Backticks are literal documentation here.
  # shellcheck disable=SC2016
  printf '\nInstall the optional shell hook so normal `codex` commands use Coralline? [y/N]: '
  IFS= read -r answer
  [[ $answer == [yY]* ]] && SHELL_REQUEST=install
  printf 'Save this configuration? [Y/n]: '; IFS= read -r answer
  if [[ $answer == [nN]* ]]; then
    printf 'No changes were written.\n'
    return 1
  fi
  CHANGES=(
    "CC_THEME=$WIZARD_THEME" "CC_STYLE=$WIZARD_STYLE" "CC_ASCII=$WIZARD_ASCII"
    "CC_SEGMENTS=$WIZARD_SEGMENTS" "CC_NODE=$WIZARD_NODE" "CC_PYTHON=$WIZARD_PYTHON"
    "CC_USAGE_REFRESH=$WIZARD_REFRESH" "CC_USAGE_STALE_AFTER=$WIZARD_STALE"
  )
}

if (($# == 0)); then WIZARD=1; fi
while (($#)); do
  case $1 in
    --wizard) WIZARD=1 ;;
    --preview) PREVIEW=1 ;;
    --theme) shift; CHANGES+=("CC_THEME=${1:?missing theme}") ;;
    --style) shift; CHANGES+=("CC_STYLE=${1:?missing style}") ;;
    --ascii) shift; CHANGES+=("CC_ASCII=${1:?missing mode}") ;;
    --node) shift; CHANGES+=("CC_NODE=${1:?missing mode}") ;;
    --python) shift; CHANGES+=("CC_PYTHON=${1:?missing mode}") ;;
    --runtime-probe) shift; CHANGES+=("CC_RUNTIME_PROBE=${1:?missing mode}") ;;
    --segments) shift; CHANGES+=("CC_SEGMENTS=${1:?missing segments}") ;;
    --usage-refresh) shift; CHANGES+=("CC_USAGE_REFRESH=${1:?missing seconds}") ;;
    --usage-stale) shift; CHANGES+=("CC_USAGE_STALE_AFTER=${1:?missing seconds}") ;;
    --shell-hook) shift; case ${1:?missing shell hook mode} in on) SHELL_REQUEST=install ;; off) SHELL_REQUEST=uninstall ;; *) printf 'shell hook must be on or off\n' >&2; exit 2 ;; esac ;;
    --show) SHOW=1 ;;
    -h | --help) usage; exit 0 ;;
    *) printf 'configure: unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

if ((WIZARD)); then visual_wizard || exit 0; fi

if ((${#CHANGES[@]})); then
  for change in "${CHANGES[@]}"; do
    key=${change%%=*}; value=${change#*=}
    case $key in
      CC_THEME) theme_exists "$value" || { printf 'unknown theme: %s\n' "$value" >&2; exit 2; } ;;
      CC_STYLE) [[ $value == powerline || $value == pill || $value == lean || $value == classic ]] || { printf 'style must be powerline, pill, lean, or classic\n' >&2; exit 2; } ;;
      CC_ASCII) [[ $value == auto || $value == on || $value == off ]] || { printf 'ascii must be auto, on, or off\n' >&2; exit 2; } ;;
      CC_NODE | CC_PYTHON | CC_RUNTIME_PROBE) [[ $value == on || $value == off ]] || { printf '%s must be on or off\n' "$key" >&2; exit 2; } ;;
      CC_SEGMENTS) segments_valid "$value" || exit 2 ;;
      CC_USAGE_REFRESH) if ! [[ $value =~ ^[0-9]+$ ]] || ((value < 30)); then printf 'usage refresh must be at least 30 seconds\n' >&2; exit 2; fi ;;
      CC_USAGE_STALE_AFTER) if ! [[ $value =~ ^[0-9]+$ ]] || ((value < 60)); then printf 'usage stale threshold must be at least 60 seconds\n' >&2; exit 2; fi ;;
    esac
  done
  result=$(python3 "$ROOT/lib/config.py" merge --config "$CONFIG" --backup-dir "$BACKUPS" "${CHANGES[@]}")
  printf '%s\n' "$result"
fi

if [ "$SHELL_REQUEST" = install ]; then
  wrapper=$(command -v coralline-codex 2>/dev/null || printf '%s' "$ROOT/bin/coralline-codex")
  real_codex=$(type -P codex || true)
  [ -n "$real_codex" ] || { printf 'configure: could not resolve the real Codex executable\n' >&2; exit 1; }
  python3 "$ROOT/lib/shell_integration.py" install --codex-home "$CODEX_DIR" \
    --backup-dir "$BACKUPS/shell" --shell auto --wrapper "$wrapper" --codex-bin "$real_codex"
elif [ "$SHELL_REQUEST" = uninstall ]; then
  python3 "$ROOT/lib/shell_integration.py" uninstall --codex-home "$CODEX_DIR" --backup-dir "$BACKUPS/shell"
fi

if ((SHOW)); then
  if [ -f "$CONFIG" ]; then sed -n '1,200p' "$CONFIG"; else printf '%s does not exist\n' "$CONFIG"; fi
fi
if ((PREVIEW)); then
  load_current
  render_preview "$CC_THEME" "$CC_STYLE" "$CC_ASCII" "$CC_SEGMENTS" "${COLUMNS:-120}"
fi

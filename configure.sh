#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
CODEX_DIR=${CODEX_HOME:-$HOME/.codex}
CONFIG=${CORALLINE_CODEX_CONFIG:-$CODEX_DIR/coralline-codex.conf}
BACKUPS=$CODEX_DIR/coralline-codex-backups
declare -a CHANGES=()

usage() {
  cat <<'EOF'
usage: configure.sh [options]
  --theme NAME            select one of the bundled themes
  --style pill|lean       select Powerlevel10k pills or a lean line
  --ascii auto|on|off     force or disable the ASCII fallback
  --node on|off           show Node when a version is reliably detected
  --python on|off         show Python when an environment/version is detected
  --runtime-probe on|off  allow node/python3 subprocess probes
  --segments "..."        set companion segment order
  --usage-refresh SECS    refresh plan-limit cache interval (minimum 30)
  --usage-stale SECS      mark cached limits stale after this age (minimum 60)
  --show                  print the effective companion configuration
EOF
}

if (($# == 0)); then
  printf 'Theme [claude-coral]: '; IFS= read -r theme; theme=${theme:-claude-coral}
  printf 'Use ASCII fallback? [y/N]: '; IFS= read -r ascii
  printf 'Show Node segment? [y/N]: '; IFS= read -r node
  printf 'Show Python segment? [y/N]: '; IFS= read -r python
  CHANGES+=("CC_THEME=$theme")
  [[ $ascii == [yY]* ]] && CHANGES+=(CC_ASCII=on) || CHANGES+=(CC_ASCII=auto)
  [[ $node == [yY]* ]] && CHANGES+=(CC_NODE=on) || CHANGES+=(CC_NODE=off)
  [[ $python == [yY]* ]] && CHANGES+=(CC_PYTHON=on) || CHANGES+=(CC_PYTHON=off)
fi
SHOW=0
while (($#)); do
  case $1 in
    --theme) shift; CHANGES+=("CC_THEME=${1:?missing theme}") ;;
    --style) shift; CHANGES+=("CC_STYLE=${1:?missing style}") ;;
    --ascii) shift; CHANGES+=("CC_ASCII=${1:?missing mode}") ;;
    --node) shift; CHANGES+=("CC_NODE=${1:?missing mode}") ;;
    --python) shift; CHANGES+=("CC_PYTHON=${1:?missing mode}") ;;
    --runtime-probe) shift; CHANGES+=("CC_RUNTIME_PROBE=${1:?missing mode}") ;;
    --segments) shift; CHANGES+=("CC_SEGMENTS=${1:?missing segments}") ;;
    --usage-refresh) shift; CHANGES+=("CC_USAGE_REFRESH=${1:?missing seconds}") ;;
    --usage-stale) shift; CHANGES+=("CC_USAGE_STALE_AFTER=${1:?missing seconds}") ;;
    --show) SHOW=1 ;;
    -h | --help) usage; exit 0 ;;
    *) printf 'configure: unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

if ((${#CHANGES[@]})); then
  for change in "${CHANGES[@]}"; do
    key=${change%%=*}; value=${change#*=}
    case $key in
      CC_THEME)
        awk -F '\t' -v wanted="$value" '$1 == wanted { found=1 } END { exit !found }' "$ROOT/themes/palettes.tsv" || { printf 'unknown theme: %s\n' "$value" >&2; exit 2; } ;;
      CC_STYLE) [[ $value == pill || $value == lean ]] || { printf 'style must be pill or lean\n' >&2; exit 2; } ;;
      CC_ASCII) [[ $value == auto || $value == on || $value == off ]] || { printf 'ascii must be auto, on, or off\n' >&2; exit 2; } ;;
      CC_NODE | CC_PYTHON | CC_RUNTIME_PROBE) [[ $value == on || $value == off ]] || { printf '%s must be on or off\n' "$key" >&2; exit 2; } ;;
      CC_USAGE_REFRESH) [[ $value =~ ^[0-9]+$ ]] && ((value >= 30)) || { printf 'usage refresh must be at least 30 seconds\n' >&2; exit 2; } ;;
      CC_USAGE_STALE_AFTER) [[ $value =~ ^[0-9]+$ ]] && ((value >= 60)) || { printf 'usage stale threshold must be at least 60 seconds\n' >&2; exit 2; } ;;
    esac
  done
  result=$(python3 "$ROOT/lib/config.py" merge --config "$CONFIG" --backup-dir "$BACKUPS" "${CHANGES[@]}")
  printf '%s\n' "$result"
fi
if ((SHOW)); then
  if [ -f "$CONFIG" ]; then sed -n '1,200p' "$CONFIG"; else printf '%s does not exist\n' "$CONFIG"; fi
fi

#!/usr/bin/env bash
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
MODE=ansi
WIDTH=${COLUMNS:-0}
CWD_VALUE=${PWD}
STATE_FILE=
AGENT_INDEX=0
CONFIG_FILE=${CORALLINE_CODEX_CONFIG:-${CODEX_HOME:-$HOME/.codex}/coralline-codex.conf}

while (($#)); do
  case $1 in
    --tmux) MODE=tmux ;;
    --plain | --no-color) MODE=plain ;;
    --width) shift; WIDTH=${1:?missing width} ;;
    --cwd) shift; CWD_VALUE=${1:?missing cwd} ;;
    --state) shift; STATE_FILE=${1:?missing state file} ;;
    --agent) shift; AGENT_INDEX=${1:?missing agent row} ;;
    --config) shift; CONFIG_FILE=${1:?missing config file} ;;
    --help)
      printf 'usage: render.sh [--tmux|--plain] [--width COLS] [--cwd DIR] [--state FILE] [--agent ROW]\n'
      exit 0 ;;
    *) printf 'coralline-codex render: unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

: "${CC_THEME:=claude-coral}"
: "${CC_STYLE:=powerline}"
: "${CC_ASCII:=auto}"
: "${CC_SEGMENTS:=limits burn tokens context dir git stash project node python model reasoning profile elapsed clock}"
: "${CC_NODE:=off}"
: "${CC_PYTHON:=off}"
: "${CC_RUNTIME_PROBE:=off}"
: "${CC_MAX_DIR:=40}"
: "${CC_NATIVE_STATUS:=on}"
: "${CC_USAGE_REFRESH:=60}"
: "${CC_USAGE_STALE_AFTER:=180}"
: "${CC_AGENTS:=on}"
: "${CC_AGENT_ROWS:=3}"
# All sourced paths are explicit configuration/cache inputs.
# shellcheck disable=SC1090
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
# shellcheck disable=SC1090
[ -n "$STATE_FILE" ] && [ -f "$STATE_FILE" ] && . "$STATE_FILE"
# shellcheck disable=SC1090
[ -n "${CORALLINE_RATE_CACHE:-}" ] && [ -f "$CORALLINE_RATE_CACHE" ] && . "$CORALLINE_RATE_CACHE"
# shellcheck disable=SC1090
[ -n "${CORALLINE_SESSION_CACHE:-}" ] && [ -f "$CORALLINE_SESSION_CACHE" ] && . "$CORALLINE_SESSION_CACHE"
# shellcheck disable=SC1090
[ -n "${CORALLINE_AGENT_CACHE:-}" ] && [ -f "$CORALLINE_AGENT_CACHE" ] && . "$CORALLINE_AGENT_CACHE"

[[ $AGENT_INDEX =~ ^[0-9]+$ ]] || { printf 'coralline-codex render: agent row must be numeric\n' >&2; exit 2; }

case $CC_ASCII in
  on | 1 | true) ASCII=1 ;;
  off | 0 | false) ASCII=0 ;;
  auto) if [[ ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} == *UTF-8* || ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} == *utf8* ]]; then ASCII=0; else ASCII=1; fi ;;
  *) printf 'coralline-codex render: CC_ASCII must be auto, on, or off\n' >&2; exit 2 ;;
esac

PALETTE_LINE=
while IFS= read -r line; do
  [[ $line == \#* || -z $line ]] && continue
  [[ ${line%%$'\t'*} == "$CC_THEME" ]] && { PALETTE_LINE=$line; break; }
done < "$ROOT/themes/palettes.tsv"
if [ -z "$PALETTE_LINE" ]; then
  printf 'coralline-codex render: unknown theme: %s\n' "$CC_THEME" >&2
  exit 2
fi
IFS=$'\t' read -r _theme C_BG C_FG C_DIR C_PROJECT C_GIT_OK C_GIT_DIRTY C_NODE C_PYTHON C_MODEL C_PROFILE C_DURATION C_CLOCK C_DIM <<< "$PALETTE_LINE"

if ! [[ $WIDTH =~ ^[0-9]+$ ]] || ((WIDTH <= 0)); then
  WIDTH=$(tput cols 2>/dev/null || printf 120)
fi

shorten_path() {
  local value=$1 max=${2:-40} home_display=$HOME
  # This tilde is intentional display text.
  # shellcheck disable=SC2088
  if [[ $value == "$home_display" ]]; then value='~';
  elif [[ $value == "$home_display"/* ]]; then value="~/${value#"$home_display"/}"; fi
  if ((${#value} > max)); then
    local tail=${value##*/} head=${value%%/*}
    [[ $value == ~/* ]] && head='~'
    local keep=$((max - ${#head} - ${#tail} - 3))
    if ((keep > 2)); then value="$head/…/${tail: -$keep}"; else value="…/${tail: -$((max-2))}"; fi
  fi
  SEG_LABEL=$value
}

git_segments() {
  SEG_GIT='' SEG_PROJECT='' SEG_STASH='' GIT_DIRTY=0
  local root status line branch='' staged=0 modified=0 untracked=0 ahead=0 behind=0
  root=$(git -C "$CWD_VALUE" rev-parse --show-toplevel 2>/dev/null) || return 0
  SEG_PROJECT=${root##*/}
  status=$(git -C "$CWD_VALUE" status --porcelain=v2 --branch 2>/dev/null) || return 0
  while IFS= read -r line; do
    case $line in
      '# branch.head '*) branch=${line#\# branch.head } ;;
      '# branch.ab '*)
        local ab=${line#\# branch.ab }
        ahead=${ab%% *}; ahead=${ahead#+}
        behind=${ab##* }; behind=${behind#-} ;;
      '? '*) ((untracked += 1)) ;;
      '1 '* | '2 '* | 'u '*)
        local xy=${line:2:2}
        [[ ${xy:0:1} != . ]] && ((staged += 1))
        [[ ${xy:1:1} != . ]] && ((modified += 1)) ;;
    esac
  done <<< "$status"
  [ -z "$branch" ] || [ "$branch" = '(detached)' ] && branch=$(git -C "$CWD_VALUE" rev-parse --short HEAD 2>/dev/null || printf detached)
  SEG_GIT=$branch
  ((staged)) && SEG_GIT+=" +$staged"
  ((modified)) && SEG_GIT+=" !$modified"
  ((untracked)) && SEG_GIT+=" ?$untracked"
  ((ahead)) && SEG_GIT+=" ↑$ahead"
  ((behind)) && SEG_GIT+=" ↓$behind"
  ((staged || modified || untracked)) && GIT_DIRTY=1
  local stash_count
  stash_count=$(git -C "$CWD_VALUE" stash list 2>/dev/null | awk 'END { print NR + 0 }')
  ((stash_count)) && SEG_STASH=$stash_count
}

node_segment() {
  SEG_LABEL=
  [ "$CC_NODE" = on ] || return 0
  local file value=
  for file in "$CWD_VALUE/.nvmrc" "$CWD_VALUE/.node-version"; do
    if [ -f "$file" ]; then IFS= read -r value < "$file" || true; break; fi
  done
  if [ -z "$value" ] && [ "$CC_RUNTIME_PROBE" = on ] && command -v node >/dev/null 2>&1; then value=$(node --version 2>/dev/null); fi
  [ -n "$value" ] && SEG_LABEL="${value#v}"
  if [ "$ASCII" = 0 ] && [ -n "$SEG_LABEL" ]; then SEG_LABEL="⬢ $SEG_LABEL";
  elif [ -n "$SEG_LABEL" ]; then SEG_LABEL="node $SEG_LABEL"; fi
}

python_segment() {
  SEG_LABEL=
  [ "$CC_PYTHON" = on ] || return 0
  local value='' file
  if [ -n "${VIRTUAL_ENV:-}" ]; then value=${VIRTUAL_ENV##*/}
  elif [ -n "${CONDA_DEFAULT_ENV:-}" ] && [ "${CONDA_DEFAULT_ENV}" != base ]; then value=$CONDA_DEFAULT_ENV
  elif [ -f "$CWD_VALUE/.python-version" ]; then IFS= read -r value < "$CWD_VALUE/.python-version" || true
  elif [ "$CC_RUNTIME_PROBE" = on ] && command -v python3 >/dev/null 2>&1; then value=$(python3 --version 2>/dev/null); value=${value#Python }; fi
  [ -n "$value" ] && SEG_LABEL="py $value"
  if [ "$ASCII" = 0 ] && [ -n "$SEG_LABEL" ]; then SEG_LABEL=" ${SEG_LABEL#py }"; fi
}

format_elapsed() {
  local start=${CORALLINE_START_EPOCH:-0} now diff h m s
  ((start > 0)) || { SEG_LABEL=; return; }
  printf -v now '%(%s)T' -1 2>/dev/null || now=$(date +%s)
  diff=$((now - start)); ((diff < 0)) && diff=0
  h=$((diff / 3600)); m=$(((diff % 3600) / 60)); s=$((diff % 60))
  if ((h)); then printf -v SEG_LABEL '%dh%02dm' "$h" "$m";
  elif ((m)); then printf -v SEG_LABEL '%dm%02ds' "$m" "$s";
  else printf -v SEG_LABEL '%ds' "$s"; fi
}

format_token_count() {
  local value=${1:-0}
  case $value in '' | *[!0-9]*) TOKEN_TEXT=; return ;; esac
  if ((value >= 1000000)); then printf -v TOKEN_TEXT '%d.%dM' $((value / 1000000)) $(((value % 1000000) / 100000));
  elif ((value >= 1000)); then printf -v TOKEN_TEXT '%d.%dk' $((value / 1000)) $(((value % 1000) / 100));
  else TOKEN_TEXT=$value; fi
}

format_reset_countdown() {
  local reset=${1:-} now diff d h m
  RESET_TEXT=
  [[ $reset =~ ^[0-9]+$ ]] || return 0
  printf -v now '%(%s)T' -1 2>/dev/null || now=$(date +%s)
  diff=$((reset - now)); ((diff <= 0)) && { RESET_TEXT=now; return; }
  d=$((diff / 86400)); h=$(((diff % 86400) / 3600)); m=$(((diff % 3600) / 60))
  if ((d)); then printf -v RESET_TEXT '%dd%02dh' "$d" "$h";
  elif ((h)); then printf -v RESET_TEXT '%dh%02dm' "$h" "$m";
  else printf -v RESET_TEXT '%dm' "$m"; fi
}

format_duration_seconds() {
  local seconds=${1:-} d h m
  DURATION_TEXT=
  [[ $seconds =~ ^[0-9]+$ ]] || return 0
  d=$((seconds / 86400)); h=$(((seconds % 86400) / 3600)); m=$(((seconds % 3600) / 60))
  if ((d)); then printf -v DURATION_TEXT '%dd%02dh' "$d" "$h";
  elif ((h)); then printf -v DURATION_TEXT '%dh%02dm' "$h" "$m";
  else printf -v DURATION_TEXT '%dm' "$m"; fi
}

make_remaining_bar() {
  local remaining=${1:-0} i filled
  [[ $remaining =~ ^[0-9]+$ ]] || remaining=0
  ((remaining < 0)) && remaining=0; ((remaining > 100)) && remaining=100
  filled=$(((remaining * 5 + 50) / 100)); REMAINING_BAR=
  for ((i = 0; i < 5; i++)); do
    if ((i < filled)); then [ "$ASCII" = 1 ] && REMAINING_BAR+='#' || REMAINING_BAR+='▰';
    else [ "$ASCII" = 1 ] && REMAINING_BAR+='-' || REMAINING_BAR+='▱'; fi
  done
}

make_used_bar() {
  local used=${1:-0} i filled
  [[ $used =~ ^[0-9]+$ ]] || used=0
  ((used < 0)) && used=0; ((used > 100)) && used=100
  filled=$(((used * 5 + 50) / 100)); USED_BAR=
  for ((i = 0; i < 5; i++)); do
    if ((i < filled)); then [ "$ASCII" = 1 ] && USED_BAR+='#' || USED_BAR+='▰';
    else [ "$ASCII" = 1 ] && USED_BAR+='-' || USED_BAR+='▱'; fi
  done
}

indirect_value() {
  local variable=$1
  INDIRECT_VALUE=${!variable-}
}

declare -a LABELS=() COLORS=()
add_segment() { [ -n "${1:-}" ] && { LABELS+=("$1"); COLORS+=("$2"); }; }
if ((AGENT_INDEX > 0)); then
  agent_prefix="CORALLINE_AGENT${AGENT_INDEX}_"
  indirect_value "${agent_prefix}NAME"; agent_name=$INDIRECT_VALUE
  indirect_value "${agent_prefix}ROLE"; agent_role=$INDIRECT_VALUE
  indirect_value "${agent_prefix}TASK"; agent_task=$INDIRECT_VALUE
  indirect_value "${agent_prefix}MODEL"; agent_model=$INDIRECT_VALUE
  indirect_value "${agent_prefix}REASONING"; agent_reasoning=$INDIRECT_VALUE
  indirect_value "${agent_prefix}STATUS"; agent_status=$INDIRECT_VALUE
  indirect_value "${agent_prefix}START_EPOCH"; agent_start=$INDIRECT_VALUE
  indirect_value "${agent_prefix}TOTAL"; agent_total=$INDIRECT_VALUE
  indirect_value "${agent_prefix}CONTEXT_USED"; agent_context_used=$INDIRECT_VALUE
  indirect_value "${agent_prefix}CONTEXT_WINDOW"; agent_context_window=$INDIRECT_VALUE
  indirect_value "${agent_prefix}DESCENDANTS"; agent_descendants=$INDIRECT_VALUE
  indirect_value "${agent_prefix}OVERFLOW"; agent_overflow=$INDIRECT_VALUE
  [ -n "$agent_name" ] || exit 0
  if [ "$ASCII" = 1 ]; then
    [ "$agent_status" = pending_init ] && SEG_LABEL="pending $agent_name" || SEG_LABEL="agent $agent_name"
  else
    [ "$agent_status" = pending_init ] && SEG_LABEL="◌ $agent_name" || SEG_LABEL="● $agent_name"
  fi
  [ -n "$agent_role" ] && SEG_LABEL+=" [$agent_role]"
  add_segment "$SEG_LABEL" "$C_PROJECT"
  if [ -n "$agent_task" ] && ((WIDTH >= 72)); then
    task_limit=$((WIDTH / 3)); ((task_limit > 42)) && task_limit=42
    ((${#agent_task} > task_limit)) && agent_task="${agent_task:0:task_limit-1}…"
    add_segment "$agent_task" "$C_DIR"
  fi
  SEG_LABEL=$agent_model
  [ -n "$agent_reasoning" ] && SEG_LABEL+=" $agent_reasoning"
  [ -n "$SEG_LABEL" ] && { [ "$ASCII" = 1 ] && SEG_LABEL="model $SEG_LABEL" || SEG_LABEL="◆ $SEG_LABEL"; }
  add_segment "$SEG_LABEL" "$C_MODEL"
  if [[ $agent_context_used =~ ^[0-9]+$ && $agent_context_window =~ ^[1-9][0-9]*$ ]]; then
    agent_context_percent=$((agent_context_used * 100 / agent_context_window))
    ((agent_context_percent > 100)) && agent_context_percent=100
    make_used_bar "$agent_context_percent"
    format_token_count "$agent_context_used"; agent_context_text=$TOKEN_TEXT
    if [ "$ASCII" = 1 ]; then SEG_LABEL="ctx $USED_BAR ${agent_context_percent}% $agent_context_text";
    else SEG_LABEL="⬡ $USED_BAR ${agent_context_percent}% $agent_context_text"; fi
    add_segment "$SEG_LABEL" "$C_PROFILE"
  elif [ -n "$agent_total" ]; then
    format_token_count "$agent_total"
    [ "$ASCII" = 1 ] && SEG_LABEL="tok $TOKEN_TEXT" || SEG_LABEL="Σ$TOKEN_TEXT"
    add_segment "$SEG_LABEL" "$C_PROFILE"
  fi
  if [[ $agent_start =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    CORALLINE_START_EPOCH=${agent_start%.*}; format_elapsed
    [ -n "$SEG_LABEL" ] && { [ "$ASCII" = 1 ] && SEG_LABEL="elapsed $SEG_LABEL" || SEG_LABEL="⧖ $SEG_LABEL"; }
    add_segment "$SEG_LABEL" "$C_DURATION"
  fi
  if [[ $agent_descendants =~ ^[1-9][0-9]*$ ]]; then
    [ "$ASCII" = 1 ] && SEG_LABEL="children $agent_descendants" || SEG_LABEL="↳$agent_descendants"
    add_segment "$SEG_LABEL" "$C_DIM"
  fi
  if [[ $agent_overflow =~ ^[1-9][0-9]*$ ]]; then
    SEG_LABEL="+$agent_overflow agents"
    add_segment "$SEG_LABEL" "$C_GIT_DIRTY"
  fi
else
git_segments
for segment in $CC_SEGMENTS; do
  SEG_LABEL='' COLOR=$C_FG
  case $segment in
    dir)
      dir_limit=$CC_MAX_DIR
      ((WIDTH > 3 && WIDTH - 3 < dir_limit)) && dir_limit=$((WIDTH - 3))
      shorten_path "$CWD_VALUE" "$dir_limit"; COLOR=$C_DIR ;;
    project) SEG_LABEL=$SEG_PROJECT; [ -n "$SEG_LABEL" ] && { [ "$ASCII" = 1 ] && SEG_LABEL="repo $SEG_LABEL" || SEG_LABEL="⬢ $SEG_LABEL"; }; COLOR=$C_PROJECT ;;
    git) SEG_LABEL=$SEG_GIT; [ -n "$SEG_LABEL" ] && { [ "$ASCII" = 1 ] && SEG_LABEL="git $SEG_LABEL" || SEG_LABEL=" $SEG_LABEL"; }; if ((GIT_DIRTY)); then COLOR=$C_GIT_DIRTY; else COLOR=$C_GIT_OK; fi ;;
    limits)
      if [ "${CORALLINE_RATE_AVAILABLE:-0}" = 1 ]; then
        printf -v rate_now '%(%s)T' -1 2>/dev/null || rate_now=$(date +%s)
        rate_updated=${CORALLINE_RATE_UPDATED:-0}
        [[ $rate_updated =~ ^[0-9]+$ ]] || rate_updated=0
        rate_age=$((rate_now - rate_updated))
        ((rate_age < 0)) && rate_age=0
        rate_stale=0
        if [[ $CC_USAGE_STALE_AFTER =~ ^[0-9]+$ ]] && ((rate_age > CC_USAGE_STALE_AFTER)); then
          rate_stale=1
        fi
        for ((limit_index = 1; limit_index <= ${CORALLINE_LIMIT_COUNT:-0}; limit_index++)); do
          indirect_value "CORALLINE_LIMIT${limit_index}_LABEL"; limit_label=$INDIRECT_VALUE
          indirect_value "CORALLINE_LIMIT${limit_index}_USED"; limit_used=$INDIRECT_VALUE
          indirect_value "CORALLINE_LIMIT${limit_index}_REMAINING"; limit_remaining=$INDIRECT_VALUE
          indirect_value "CORALLINE_LIMIT${limit_index}_RESET"; limit_reset=$INDIRECT_VALUE
          [ -n "$limit_remaining" ] || continue
          make_remaining_bar "$limit_remaining"
          format_reset_countdown "$limit_reset"
          if ((WIDTH < 45)); then
            SEG_LABEL="$limit_label ${limit_remaining}%"
          elif ((WIDTH < 80)); then
            SEG_LABEL="$limit_label ${limit_remaining}%"
            [ -n "$RESET_TEXT" ] && SEG_LABEL+=" ↺$RESET_TEXT"
          else
            if [ "$ASCII" = 1 ]; then SEG_LABEL="$limit_label $REMAINING_BAR ${limit_remaining}% left";
            else SEG_LABEL="$limit_label $REMAINING_BAR ${limit_remaining}%"; fi
            [ -n "$RESET_TEXT" ] && SEG_LABEL+=" ↺$RESET_TEXT"
          fi
          if ((rate_stale)); then
            if ((rate_age >= 3600)); then rate_stale_text="$((rate_age / 3600))h";
            elif ((rate_age >= 60)); then rate_stale_text="$((rate_age / 60))m";
            else rate_stale_text="${rate_age}s"; fi
            if [ "$ASCII" = 1 ]; then SEG_LABEL+=" stale:$rate_stale_text";
            else SEG_LABEL+=" ⚠$rate_stale_text"; fi
            COLOR=$C_GIT_DIRTY
          elif ((limit_used >= 75)); then COLOR=$C_GIT_DIRTY;
          elif ((limit_used >= 50)); then COLOR=$C_PROFILE;
          else COLOR=$C_GIT_OK; fi
          add_segment "$SEG_LABEL" "$COLOR"
        done
      fi
      continue ;;
    tokens)
      SEG_LABEL=
      if [ "${CORALLINE_SESSION_AVAILABLE:-0}" = 1 ]; then
        format_token_count "${CORALLINE_SESSION_TOTAL:-}"; token_total=$TOKEN_TEXT
        format_token_count "${CORALLINE_SESSION_INPUT:-}"; token_input=$TOKEN_TEXT
        format_token_count "${CORALLINE_SESSION_OUTPUT:-}"; token_output=$TOKEN_TEXT
        if [ -n "$token_total" ]; then
          if ((WIDTH < 80)); then
            if [ "$ASCII" = 1 ]; then SEG_LABEL="tok $token_total"; else SEG_LABEL="Σ$token_total"; fi
          elif [ "$ASCII" = 1 ]; then SEG_LABEL="tok $token_total in:$token_input out:$token_output";
          else SEG_LABEL="Σ$token_total ↑$token_input ↓$token_output"; fi
        fi
      fi
      COLOR=$C_MODEL ;;
    context)
      SEG_LABEL=
      if [[ ${CORALLINE_CONTEXT_USED:-} =~ ^[0-9]+$ && ${CORALLINE_CONTEXT_WINDOW:-} =~ ^[1-9][0-9]*$ ]]; then
        context_percent=$((CORALLINE_CONTEXT_USED * 100 / CORALLINE_CONTEXT_WINDOW))
        ((context_percent > 100)) && context_percent=100
        make_used_bar "$context_percent"
        format_token_count "$CORALLINE_CONTEXT_USED"; context_text=$TOKEN_TEXT
        if [ "$ASCII" = 1 ]; then SEG_LABEL="ctx $USED_BAR ${context_percent}% $context_text";
        else SEG_LABEL="⬡ $USED_BAR ${context_percent}% $context_text"; fi
      fi
      COLOR=$C_PROFILE ;;
    burn)
      if [ "${CORALLINE_RATE_AVAILABLE:-0}" = 1 ]; then
        for ((limit_index = 1; limit_index <= ${CORALLINE_LIMIT_COUNT:-0}; limit_index++)); do
          indirect_value "CORALLINE_LIMIT${limit_index}_LABEL"; burn_label=$INDIRECT_VALUE
          indirect_value "CORALLINE_LIMIT${limit_index}_BURN_STATE"; burn_state=$INDIRECT_VALUE
          indirect_value "CORALLINE_LIMIT${limit_index}_BURN_ETA"; burn_eta=$INDIRECT_VALUE
          case $burn_state in
            tracking)
              format_duration_seconds "$burn_eta"
              [ -n "$DURATION_TEXT" ] || continue
              if [ "$ASCII" = 1 ]; then SEG_LABEL="burn $burn_label $DURATION_TEXT";
              else SEG_LABEL="↗$burn_label $DURATION_TEXT"; fi
              COLOR=$C_PROFILE ;;
            safe)
              if [ "$ASCII" = 1 ]; then SEG_LABEL="burn $burn_label reset-safe";
              else SEG_LABEL="✓$burn_label reset-safe"; fi
              COLOR=$C_GIT_OK ;;
            idle)
              if [ "$ASCII" = 1 ]; then SEG_LABEL="burn $burn_label idle";
              else SEG_LABEL="✓$burn_label idle"; fi
              COLOR=$C_GIT_OK ;;
            warming)
              if [ "$ASCII" = 1 ]; then SEG_LABEL="burn $burn_label warming";
              else SEG_LABEL="↗$burn_label warm"; fi
              COLOR=$C_DIM ;;
            *) continue ;;
          esac
          if ((WIDTH < 45)); then
            case $burn_state in
              tracking) SEG_LABEL="↗$burn_label $DURATION_TEXT" ;;
              safe | idle) SEG_LABEL="✓$burn_label" ;;
              warming) SEG_LABEL="…$burn_label" ;;
            esac
          fi
          add_segment "$SEG_LABEL" "$COLOR"
        done
      fi
      continue ;;
    node) node_segment; COLOR=$C_NODE ;;
    python) python_segment; COLOR=$C_PYTHON ;;
    stash) SEG_LABEL=$SEG_STASH; [ -n "$SEG_LABEL" ] && { [ "$ASCII" = 1 ] && SEG_LABEL="stash $SEG_LABEL" || SEG_LABEL="≡ $SEG_LABEL"; }; COLOR=$C_PROFILE ;;
    model) SEG_LABEL=${CORALLINE_MODEL:-}; [ -n "$SEG_LABEL" ] && SEG_LABEL="model $SEG_LABEL"; COLOR=$C_MODEL ;;
    reasoning) SEG_LABEL=${CORALLINE_REASONING:-}; [[ -n "$SEG_LABEL" && $SEG_LABEL != auto ]] && SEG_LABEL="reason $SEG_LABEL" || SEG_LABEL=; COLOR=$C_MODEL ;;
    profile) SEG_LABEL=${CORALLINE_PROFILE:-}; [ -n "$SEG_LABEL" ] && SEG_LABEL="profile $SEG_LABEL"; COLOR=$C_PROFILE ;;
    elapsed) format_elapsed; [ -n "$SEG_LABEL" ] && { [ "$ASCII" = 1 ] && SEG_LABEL="elapsed $SEG_LABEL" || SEG_LABEL="⧖ $SEG_LABEL"; }; COLOR=$C_DURATION ;;
    clock) printf -v SEG_LABEL '%(%H:%M)T' -1 2>/dev/null || SEG_LABEL=$(date +%H:%M); [ "$ASCII" = 1 ] && SEG_LABEL="time $SEG_LABEL" || SEG_LABEL="◷ $SEG_LABEL"; COLOR=$C_CLOCK ;;
    *) continue ;;
  esac
  add_segment "$SEG_LABEL" "$COLOR"
done
fi

declare -a KEEP_LABELS=() KEEP_COLORS=()
used=0
for i in "${!LABELS[@]}"; do
  label=${LABELS[$i]}
  cost=$((${#label} + 3))
  ((used && (cost += 1)))
  if ((used + cost <= WIDTH)) || ((${#KEEP_LABELS[@]} == 0)); then
    KEEP_LABELS+=("$label"); KEEP_COLORS+=("${COLORS[$i]}"); used=$((used + cost))
  fi
done

hex_to_rgb() {
  local hex=${1#\#}
  RGB_R=$((16#${hex:0:2})); RGB_G=$((16#${hex:2:2})); RGB_B=$((16#${hex:4:2}))
}

out=
for i in "${!KEEP_LABELS[@]}"; do
  label=${KEEP_LABELS[$i]} color=${KEEP_COLORS[$i]}
  if [ "$MODE" = plain ]; then
    [ -n "$out" ] && out+=' | '
    out+=$label
  elif [ "$MODE" = tmux ]; then
    label=${label//'#'/'##'}
    if [ "$ASCII" = 1 ]; then
      out+="#[fg=$color,bold][ $label ]#[default] "
    elif [ "$CC_STYLE" = powerline ]; then
      next_color=$C_BG
      if ((i + 1 < ${#KEEP_LABELS[@]})); then next_color=${KEEP_COLORS[i + 1]}; fi
      out+="#[fg=$C_FG,bg=$color,bold] $label #[fg=$color,bg=$next_color,nobold]"
      if ((i + 1 == ${#KEEP_LABELS[@]})); then out+="#[default]"; fi
    elif [ "$CC_STYLE" = lean ]; then
      [ -n "$out" ] && out+="#[fg=$C_DIM] · "
      out+="#[fg=$color,bold]$label#[default]"
    elif [ "$CC_STYLE" = classic ]; then
      out+="#[fg=$C_FG,bg=$color,bold] $label #[default] "
    else
      out+="#[fg=$color]#[fg=$C_FG,bg=$color,bold] $label #[fg=$color,bg=$C_BG,nobold]#[default] "
    fi
  else
    hex_to_rgb "$color"; bg="\033[48;2;${RGB_R};${RGB_G};${RGB_B}m"; fgcap="\033[38;2;${RGB_R};${RGB_G};${RGB_B}m"
    hex_to_rgb "$C_FG"; fgtext="\033[38;2;${RGB_R};${RGB_G};${RGB_B}m"
    if [ "$ASCII" = 1 ]; then out+="\033[1m${fgcap}[ $label ]\033[0m ";
    elif [ "$CC_STYLE" = powerline ]; then
      next_color=$C_BG
      if ((i + 1 < ${#KEEP_LABELS[@]})); then next_color=${KEEP_COLORS[i + 1]}; fi
      hex_to_rgb "$next_color"; next_bg="\033[48;2;${RGB_R};${RGB_G};${RGB_B}m"
      out+="${bg}${fgtext}\033[1m $label \033[22m${fgcap}${next_bg}"
      if ((i + 1 == ${#KEEP_LABELS[@]})); then out+="\033[0m"; fi
    elif [ "$CC_STYLE" = lean ]; then [ -n "$out" ] && out+=" \033[0m· "; out+="\033[1m${fgcap}$label\033[0m";
    elif [ "$CC_STYLE" = classic ]; then out+="${bg}${fgtext}\033[1m $label \033[0m ";
    else out+="${fgcap}${bg}${fgtext}\033[1m $label \033[0m${fgcap}\033[0m "; fi
  fi
done
printf '%b\n' "$out"

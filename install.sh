#!/usr/bin/env bash
set -euo pipefail

SOURCE=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
CODEX_DIR=${CODEX_HOME:-$HOME/.codex}
BIN_DIR=${CORALLINE_BIN_DIR:-$HOME/.local/bin}
MODE=install
SHELL_HOOK=preserve

canonical_path() {
  python3 - "$1" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).resolve())
PY
}

usage() {
  cat <<'EOF'
usage: install.sh [--codex-home PATH] [--bin-dir PATH] [--update|--uninstall]
                  [--shell-hook auto|bash|zsh|none]

Installs from this checked-out source tree. No remote script execution is used.
EOF
}
while (($#)); do
  case $1 in
    --codex-home) shift; CODEX_DIR=${1:?missing path} ;;
    --bin-dir) shift; BIN_DIR=${1:?missing path} ;;
    --update) MODE=update ;;
    --uninstall) MODE=uninstall ;;
    --shell-hook) shift; SHELL_HOOK=${1:?missing shell hook mode} ;;
    -h | --help) usage; exit 0 ;;
    *) printf 'install: unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done
case $SHELL_HOOK in preserve | auto | bash | zsh | none) ;; *) printf 'install: invalid shell hook mode: %s\n' "$SHELL_HOOK" >&2; exit 2 ;; esac

INSTALL_DIR=$CODEX_DIR/coralline-codex
CONFIG=$CODEX_DIR/coralline-codex.conf
THEME_DIR=$CODEX_DIR/themes
BACKUP_ROOT=$CODEX_DIR/coralline-codex-backups
BIN=$BIN_DIR/coralline-codex
EXPECTED_BIN=$(canonical_path "$INSTALL_DIR/bin/coralline-codex")
WINDOWS_SHELL=0
case $(uname -s) in MINGW* | MSYS* | CYGWIN*) WINDOWS_SHELL=1 ;; esac
MANAGED_SHIM_MARKER='# coralline-codex managed Git Bash shim'

bin_is_managed() {
  if [ -L "$BIN" ]; then
    [ "$(canonical_path "$BIN")" = "$EXPECTED_BIN" ]
  elif ((WINDOWS_SHELL)) && [ -f "$BIN" ]; then
    grep -Fqx "$MANAGED_SHIM_MARKER" "$BIN"
  else
    return 1
  fi
}

install_command() {
  if ((WINDOWS_SHELL)); then
    {
      printf '#!/usr/bin/env bash\n%s\nexec ' "$MANAGED_SHIM_MARKER"
      printf '%q ' "$INSTALL_DIR/bin/coralline-codex"
      printf '"$@"\n'
    } > "$BIN"
    chmod 755 "$BIN"
  else
    ln -sfn -- "$INSTALL_DIR/bin/coralline-codex" "$BIN"
  fi
}

previous_version=
[ -f "$INSTALL_DIR/VERSION" ] && IFS= read -r previous_version < "$INSTALL_DIR/VERSION"
stamp=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=$BACKUP_ROOT/$stamp
counter=1
while [ -e "$BACKUP_DIR" ]; do
  BACKUP_DIR=$BACKUP_ROOT/$stamp.$counter
  counter=$((counter + 1))
done

if [ "$MODE" = uninstall ]; then
  [ -d "$INSTALL_DIR" ] || { printf 'coralline-codex is not installed in %s\n' "$CODEX_DIR"; exit 0; }
  mkdir -p "$BACKUP_DIR"
  if [ -x "$INSTALL_DIR/lib/shell_integration.py" ]; then
    python3 "$INSTALL_DIR/lib/shell_integration.py" uninstall \
      --codex-home "$CODEX_DIR" --backup-dir "$BACKUP_ROOT/shell" || true
  fi
  if [ -f "$CONFIG" ]; then mv -- "$CONFIG" "$BACKUP_DIR/coralline-codex.conf"; fi
  mkdir -p "$BACKUP_DIR/themes"
  while IFS=$'\t' read -r theme_name _; do
    [[ $theme_name == \#* || -z $theme_name ]] && continue
    theme=$THEME_DIR/coralline-$theme_name.tmTheme
    [ -e "$theme" ] && mv -- "$theme" "$BACKUP_DIR/themes/"
  done < "$INSTALL_DIR/themes/palettes.tsv"
  if bin_is_managed; then rm -f -- "$BIN"; fi
  mv -- "$INSTALL_DIR" "$BACKUP_DIR/install"
  printf 'Uninstalled Coralline Codex. Recoverable backup: %s\n' "$BACKUP_DIR"
  printf 'Codex config.toml was not changed.\n'
  exit 0
fi

for dependency in bash python3 codex; do
  command -v "$dependency" >/dev/null 2>&1 || { printf 'install: required command not found: %s\n' "$dependency" >&2; exit 1; }
done
mkdir -p "$CODEX_DIR" "$BIN_DIR" "$THEME_DIR"
if { [ -e "$BIN" ] || [ -L "$BIN" ]; } && ! bin_is_managed; then
  printf 'install: refusing to overwrite unrelated path: %s\n' "$BIN" >&2
  exit 1
fi
if [ ! -d "$INSTALL_DIR" ]; then
  while IFS=$'\t' read -r theme_name _; do
    [[ $theme_name == \#* || -z $theme_name ]] && continue
    if [ -e "$THEME_DIR/coralline-$theme_name.tmTheme" ]; then
      printf 'install: refusing to overwrite unrelated theme: %s\n' "$THEME_DIR/coralline-$theme_name.tmTheme" >&2
      exit 1
    fi
  done < "$SOURCE/themes/palettes.tsv"
fi

stage=$(mktemp -d "$CODEX_DIR/.coralline-codex-stage.XXXXXX")
cleanup() { if [ -n "$stage" ] && [ -d "$stage" ]; then rm -rf -- "$stage"; fi; }
trap cleanup EXIT
mkdir -p "$stage/bin" "$stage/lib" "$stage/themes" "$stage/tools" "$stage/test" "$stage/docs" "$stage/assets"
for file in VERSION CHANGELOG.md CONTRIBUTING.md LICENSE NOTICE.md README.md README.zh-TW.md SECURITY.md install.sh install.ps1 configure.sh configure.ps1; do
  [ -f "$SOURCE/$file" ] && cp -p -- "$SOURCE/$file" "$stage/"
done
cp -p -- "$SOURCE/bin/coralline-codex" "$stage/bin/"
cp -p -- "$SOURCE/bin/coralline-codex.ps1" "$stage/bin/"
cp -p -- "$SOURCE/lib/config.py" "$SOURCE/lib/render.sh" "$SOURCE/lib/shell_integration.py" "$SOURCE/lib/usage.py" "$stage/lib/"
cp -p -- "$SOURCE/themes/palettes.tsv" "$stage/themes/"
cp -p -- "$SOURCE/tools/generate_themes.py" "$stage/tools/"
cp -p -- "$SOURCE/tools/render_assets.py" "$stage/tools/"
cp -p -- "$SOURCE/assets/"*.svg "$stage/assets/"
cp -p -- "$SOURCE/test/verify-install.sh" "$stage/test/"
if [ -d "$SOURCE/docs" ]; then
  cp -p -- "$SOURCE/docs/"* "$stage/docs/"
fi
chmod 755 "$stage/bin/coralline-codex" "$stage/lib/render.sh" "$stage/lib/config.py" "$stage/lib/shell_integration.py" "$stage/lib/usage.py" "$stage/tools/generate_themes.py" "$stage/tools/render_assets.py" "$stage/install.sh" "$stage/configure.sh" "$stage/test/verify-install.sh"
python3 "$stage/tools/generate_themes.py" --palettes "$stage/themes/palettes.tsv" --output "$stage/themes/generated"

if [ -d "$INSTALL_DIR" ]; then
  mkdir -p "$BACKUP_DIR"
  mv -- "$INSTALL_DIR" "$BACKUP_DIR/install"
fi
mv -- "$stage" "$INSTALL_DIR"
stage=

mkdir -p "$THEME_DIR"
for theme in "$INSTALL_DIR/themes/generated/"*.tmTheme; do
  target=$THEME_DIR/${theme##*/}
  if [ -e "$target" ]; then mkdir -p "$BACKUP_DIR/themes"; cp -p -- "$target" "$BACKUP_DIR/themes/"; fi
  cp -p -- "$theme" "$target"
done

if [ ! -f "$CONFIG" ]; then
  python3 "$INSTALL_DIR/lib/config.py" merge --config "$CONFIG" --backup-dir "$BACKUP_ROOT" \
    CC_THEME=claude-coral CC_STYLE=powerline CC_ASCII=auto CC_NODE=off CC_PYTHON=off \
    CC_RUNTIME_PROBE=off 'CC_SEGMENTS=limits burn tokens dir git project node python model profile elapsed clock' \
    CC_NATIVE_STATUS=on CC_USAGE_REFRESH=60 CC_USAGE_STALE_AFTER=180 >/dev/null
elif grep -Fxq "CC_SEGMENTS='dir project git node python model profile elapsed clock'" "$CONFIG"; then
  python3 "$INSTALL_DIR/lib/config.py" merge --config "$CONFIG" --backup-dir "$BACKUP_ROOT" \
    'CC_SEGMENTS=limits burn tokens dir git project node python model profile elapsed clock' \
    CC_USAGE_REFRESH=60 CC_USAGE_STALE_AFTER=180 >/dev/null
elif grep -Fxq "CC_SEGMENTS='limits tokens dir git project node python model profile elapsed clock'" "$CONFIG"; then
  python3 "$INSTALL_DIR/lib/config.py" merge --config "$CONFIG" --backup-dir "$BACKUP_ROOT" \
    'CC_SEGMENTS=limits burn tokens dir git project node python model profile elapsed clock' >/dev/null
fi
install_command
if [ "$SHELL_HOOK" = none ]; then
  python3 "$INSTALL_DIR/lib/shell_integration.py" uninstall \
    --codex-home "$CODEX_DIR" --backup-dir "$BACKUP_ROOT/shell"
elif [ "$SHELL_HOOK" != preserve ]; then
  real_codex=$(type -P codex || true)
  [ -n "$real_codex" ] || { printf 'install: could not resolve the real Codex binary for shell integration\n' >&2; exit 1; }
  shell_rc_args=()
  case $SHELL_HOOK in
    bash) shell_rc_args=(--rc "$HOME/.bashrc") ;;
    zsh) shell_rc_args=(--rc "$HOME/.zshrc") ;;
    auto)
      case ${SHELL##*/} in
        bash) shell_rc_args=(--rc "$HOME/.bashrc") ;;
        zsh) shell_rc_args=(--rc "$HOME/.zshrc") ;;
      esac ;;
  esac
  python3 "$INSTALL_DIR/lib/shell_integration.py" install \
    --codex-home "$CODEX_DIR" --backup-dir "$BACKUP_ROOT/shell" \
    --shell "$SHELL_HOOK" "${shell_rc_args[@]}" --wrapper "$BIN" --codex-bin "$real_codex"
fi

printf 'Coralline Codex %s installed.\n' "$(< "$INSTALL_DIR/VERSION")"
printf '  command: %s\n  runtime: %s\n  config:  %s\n' "$BIN" "$INSTALL_DIR" "$CONFIG"
if [ -d "$BACKUP_DIR" ]; then printf '  backup:  %s\n' "$BACKUP_DIR"; else printf '  backup:  none (no existing files were replaced)\n'; fi
printf '  Codex config.toml: unchanged (native settings are scoped CLI overrides)\n'
current_version=$(< "$INSTALL_DIR/VERSION")
if [ -n "$previous_version" ] && [ "$previous_version" != "$current_version" ]; then
  printf '\nUpdated %s -> %s. New in this release:\n' "$previous_version" "$current_version"
  awk -v wanted="$current_version" '
    index($0, "## " wanted " ") == 1 { show=1; next }
    show && /^## / { exit }
    show && /^- / { print "  " $0 }
  ' "$INSTALL_DIR/CHANGELOG.md"
fi
if ! command -v tmux >/dev/null 2>&1; then
  printf '  note: tmux is absent; the themed native Codex footer works, but the companion bar will fall back to one-shot rendering.\n'
fi

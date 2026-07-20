#!/usr/bin/env bash
set -euo pipefail

SOURCE=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
CODEX_DIR=${CODEX_HOME:-$HOME/.codex}
BIN_DIR=${CORALLINE_BIN_DIR:-$HOME/.local/bin}
MODE=install

usage() {
  cat <<'EOF'
usage: install.sh [--codex-home PATH] [--bin-dir PATH] [--update|--uninstall]

Installs from this checked-out source tree. No remote script execution is used.
EOF
}
while (($#)); do
  case $1 in
    --codex-home) shift; CODEX_DIR=${1:?missing path} ;;
    --bin-dir) shift; BIN_DIR=${1:?missing path} ;;
    --update) MODE=update ;;
    --uninstall) MODE=uninstall ;;
    -h | --help) usage; exit 0 ;;
    *) printf 'install: unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

INSTALL_DIR=$CODEX_DIR/coralline-codex
CONFIG=$CODEX_DIR/coralline-codex.conf
THEME_DIR=$CODEX_DIR/themes
BACKUP_ROOT=$CODEX_DIR/coralline-codex-backups
BIN=$BIN_DIR/coralline-codex
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
  if [ -f "$CONFIG" ]; then mv -- "$CONFIG" "$BACKUP_DIR/coralline-codex.conf"; fi
  mkdir -p "$BACKUP_DIR/themes"
  while IFS=$'\t' read -r theme_name _; do
    [[ $theme_name == \#* || -z $theme_name ]] && continue
    theme=$THEME_DIR/coralline-$theme_name.tmTheme
    [ -e "$theme" ] && mv -- "$theme" "$BACKUP_DIR/themes/"
  done < "$INSTALL_DIR/themes/palettes.tsv"
  if [ -L "$BIN" ] && [ "$(readlink -f -- "$BIN")" = "$INSTALL_DIR/bin/coralline-codex" ]; then unlink -- "$BIN"; fi
  mv -- "$INSTALL_DIR" "$BACKUP_DIR/install"
  printf 'Uninstalled Coralline Codex. Recoverable backup: %s\n' "$BACKUP_DIR"
  printf 'Codex config.toml was not changed.\n'
  exit 0
fi

for dependency in bash python3 codex; do
  command -v "$dependency" >/dev/null 2>&1 || { printf 'install: required command not found: %s\n' "$dependency" >&2; exit 1; }
done
mkdir -p "$CODEX_DIR" "$BIN_DIR" "$THEME_DIR"
if [ -e "$BIN" ] && { [ ! -L "$BIN" ] || [ "$(readlink -f -- "$BIN")" != "$INSTALL_DIR/bin/coralline-codex" ]; }; then
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
mkdir -p "$stage/bin" "$stage/lib" "$stage/themes" "$stage/tools" "$stage/test" "$stage/docs"
for file in VERSION LICENSE NOTICE.md README.md README.zh-TW.md install.sh configure.sh; do
  [ -f "$SOURCE/$file" ] && cp -p -- "$SOURCE/$file" "$stage/"
done
cp -p -- "$SOURCE/bin/coralline-codex" "$stage/bin/"
cp -p -- "$SOURCE/lib/config.py" "$SOURCE/lib/render.sh" "$stage/lib/"
cp -p -- "$SOURCE/themes/palettes.tsv" "$stage/themes/"
cp -p -- "$SOURCE/tools/generate_themes.py" "$stage/tools/"
cp -p -- "$SOURCE/test/verify-install.sh" "$stage/test/"
[ -d "$SOURCE/docs" ] && cp -p -- "$SOURCE/docs/"* "$stage/docs/" 2>/dev/null || true
chmod 755 "$stage/bin/coralline-codex" "$stage/lib/render.sh" "$stage/lib/config.py" "$stage/tools/generate_themes.py" "$stage/install.sh" "$stage/configure.sh" "$stage/test/verify-install.sh"
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
    CC_THEME=claude-coral CC_STYLE=pill CC_ASCII=auto CC_NODE=off CC_PYTHON=off \
    CC_RUNTIME_PROBE=off 'CC_SEGMENTS=dir project git node python model profile elapsed clock' \
    CC_NATIVE_STATUS=on >/dev/null
fi
ln -sfn -- "$INSTALL_DIR/bin/coralline-codex" "$BIN"

printf 'Coralline Codex %s installed.\n' "$(< "$INSTALL_DIR/VERSION")"
printf '  command: %s\n  runtime: %s\n  config:  %s\n' "$BIN" "$INSTALL_DIR" "$CONFIG"
if [ -d "$BACKUP_DIR" ]; then printf '  backup:  %s\n' "$BACKUP_DIR"; else printf '  backup:  none (no existing files were replaced)\n'; fi
printf '  Codex config.toml: unchanged (native settings are scoped CLI overrides)\n'
if ! command -v tmux >/dev/null 2>&1; then
  printf '  note: tmux is absent; the themed native Codex footer works, but the companion bar will fall back to one-shot rendering.\n'
fi

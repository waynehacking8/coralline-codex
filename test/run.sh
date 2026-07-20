#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/coralline-codex-tests.XXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT
passes=0

pass() { printf 'ok %02d - %s\n' "$((++passes))" "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
assert_contains() { [[ $1 == *"$2"* ]] || fail "$3 (missing: $2)"; }
assert_not_contains() { [[ $1 != *"$2"* ]] || fail "$3 (unexpected: $2)"; }
assert_file() { [ -f "$1" ] || fail "$2 ($1)"; }
assert_absent() { [ ! -e "$1" ] && [ ! -L "$1" ] || fail "$2 ($1)"; }

bash -n "$ROOT/bin/coralline-codex" "$ROOT/lib/render.sh" "$ROOT/configure.sh" \
  "$ROOT/install.sh" "$ROOT/test/verify-install.sh" "$0"
python3 -m py_compile "$ROOT/lib/config.py" "$ROOT/tools/generate_themes.py"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$ROOT/bin/coralline-codex" "$ROOT/lib/render.sh" "$ROOT/configure.sh" \
    "$ROOT/install.sh" "$ROOT/test/verify-install.sh"
fi
pass 'shell and Python lint/syntax checks'

if command -v tmux >/dev/null 2>&1 && command -v script >/dev/null 2>&1; then
  printf -v tty_command '%q --version' "$ROOT/bin/coralline-codex"
  tty_output=$(TERM=xterm-256color timeout 10 script -qfec "$tty_command" /dev/null 2>&1)
  assert_contains "$tty_output" 'codex-cli ' 'tmux companion launches Codex in a pseudo-terminal'
  assert_not_contains "$tty_output" 'unbound variable' 'tmux companion cleanup is scoped'
  pass 'isolated tmux companion launch and cleanup'
fi

while IFS=$'\t' read -r theme _; do
  [[ $theme == \#* || -z $theme ]] && continue
  output=$(CC_THEME=$theme CC_ASCII=on CORALLINE_CODEX_CONFIG=/dev/null \
    CORALLINE_START_EPOCH=$(date +%s) CORALLINE_MODEL=test-model CORALLINE_PROFILE=test \
    "$ROOT/lib/render.sh" --plain --width 240 --cwd "$ROOT")
  assert_contains "$output" 'test-model' "theme $theme renders"
done < "$ROOT/themes/palettes.tsv"
pass 'all nine themes render'

width_output=$(CC_ASCII=on CORALLINE_CODEX_CONFIG=/dev/null \
  "$ROOT/lib/render.sh" --plain --width 30 --cwd "$TEST_ROOT/a directory with spaces/and-a-long-tail")
width_count=$(python3 -c 'import sys; print(len(sys.stdin.read().rstrip("\n")))' <<< "$width_output")
((width_count <= 30)) || fail "width handling exceeded limit: $width_count"
pass 'width handling and paths with spaces'

repo="$TEST_ROOT/git states"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email tests@example.invalid
git -C "$repo" config user.name Tests
printf 'base\n' > "$repo/tracked"
git -C "$repo" add tracked
git -C "$repo" commit -qm base
clean=$(CC_ASCII=on CC_SEGMENTS='git' CORALLINE_CODEX_CONFIG=/dev/null "$ROOT/lib/render.sh" --plain --width 120 --cwd "$repo")
assert_contains "$clean" 'git ' 'clean Git branch renders'
printf 'modified\n' >> "$repo/tracked"
printf 'staged\n' > "$repo/staged"
printf 'new\n' > "$repo/untracked"
git -C "$repo" add staged
dirty=$(CC_ASCII=on CC_SEGMENTS='git' CORALLINE_CODEX_CONFIG=/dev/null "$ROOT/lib/render.sh" --plain --width 120 --cwd "$repo")
assert_contains "$dirty" '+1' 'staged count renders'
assert_contains "$dirty" '!1' 'modified count renders'
assert_contains "$dirty" '?1' 'untracked count renders'
git -C "$repo" checkout -q --detach HEAD
detached=$(CC_ASCII=on CC_SEGMENTS='git' CORALLINE_CODEX_CONFIG=/dev/null "$ROOT/lib/render.sh" --plain --width 120 --cwd "$repo")
assert_contains "$detached" "$(git -C "$repo" rev-parse --short HEAD)" 'detached HEAD renders'
pass 'clean, dirty, and detached Git states'

empty="$TEST_ROOT/no runtimes"
mkdir -p "$empty"
missing=$(env -u VIRTUAL_ENV -u CONDA_DEFAULT_ENV CC_ASCII=on CC_NODE=on CC_PYTHON=on \
  CC_RUNTIME_PROBE=off CC_SEGMENTS='node python' CORALLINE_CODEX_CONFIG=/dev/null \
  "$ROOT/lib/render.sh" --plain --width 120 --cwd "$empty")
assert_not_contains "$missing" 'node' 'missing Node hides segment'
assert_not_contains "$missing" 'py ' 'missing Python hides segment'
pass 'missing optional data degrades without fabricated values'

config_dir="$TEST_ROOT/config merge"
mkdir -p "$config_dir/backups"
config="$config_dir/custom config.conf"
cat > "$config" <<'EOF'
# user comment
CC_THEME=mono
CUSTOM_KEEP='value with spaces'
CC_NODE=off
EOF
before=$(sha256sum "$config" | awk '{print $1}')
python3 "$ROOT/lib/config.py" merge --config "$config" --backup-dir "$config_dir/backups" \
  CC_THEME=nord CC_NODE=on >/dev/null
merged=$(< "$config")
assert_contains "$merged" '# user comment' 'config comments preserved'
assert_contains "$merged" "CUSTOM_KEEP='value with spaces'" 'unknown config preserved'
assert_contains "$merged" 'CC_THEME=nord' 'known config replaced'
backup=$(find "$config_dir/backups" -type f -name 'custom config.conf.bak.*' -print -quit)
assert_file "$backup" 'config backup created'
after_backup=$(sha256sum "$backup" | awk '{print $1}')
[ "$before" = "$after_backup" ] || fail 'config backup is not byte-identical'
pass 'configuration merging preserves unrelated data and backs up first'

codex_home="$TEST_ROOT/Codex Home"
bin_dir="$TEST_ROOT/bin with spaces"
mkdir -p "$codex_home" "$bin_dir"
cat > "$codex_home/config.toml" <<'EOF'
model = "gpt-5.6"
approval_policy = "never"

[mcp_servers.example]
command = "printf"
args = ["path with spaces"]
EOF
codex_config_hash=$(sha256sum "$codex_home/config.toml" | awk '{print $1}')
CODEX_HOME="$codex_home" CORALLINE_BIN_DIR="$bin_dir" "$ROOT/install.sh" >/dev/null
assert_file "$codex_home/coralline-codex/VERSION" 'fresh install runtime'
[ -L "$bin_dir/coralline-codex" ] || fail 'fresh install command symlink'
generated_count=$(find "$codex_home/themes" -name 'coralline-*.tmTheme' -type f | wc -l)
((generated_count == 9)) || fail "expected 9 generated themes, got $generated_count"
[ "$codex_config_hash" = "$(sha256sum "$codex_home/config.toml" | awk '{print $1}')" ] || fail 'install changed config.toml'
CODEX_HOME="$codex_home" CORALLINE_BIN_DIR="$bin_dir" "$bin_dir/coralline-codex" verify >/dev/null
pass 'isolated fresh install and strict Codex verification'

printf 'local marker\n' >> "$codex_home/coralline-codex/VERSION"
CODEX_HOME="$codex_home" CORALLINE_BIN_DIR="$bin_dir" "$ROOT/install.sh" --update >/dev/null
backup_install=$(find "$codex_home/coralline-codex-backups" -path '*/install/VERSION' -print -quit)
assert_file "$backup_install" 'upgrade runtime backup'
assert_contains "$(< "$backup_install")" 'local marker' 'upgrade retained exact old runtime'
assert_not_contains "$(< "$codex_home/coralline-codex/VERSION")" 'local marker' 'upgrade installed new runtime'
[ "$codex_config_hash" = "$(sha256sum "$codex_home/config.toml" | awk '{print $1}')" ] || fail 'upgrade changed config.toml'
pass 'upgrade replaces owned runtime and preserves Codex configuration'

CODEX_HOME="$codex_home" CORALLINE_BIN_DIR="$bin_dir" "$codex_home/coralline-codex/install.sh" --uninstall >/dev/null
assert_absent "$codex_home/coralline-codex" 'uninstall runtime removal'
assert_absent "$bin_dir/coralline-codex" 'uninstall command removal'
assert_absent "$codex_home/coralline-codex.conf" 'uninstall config removal'
remaining_themes=$(find "$codex_home/themes" -name 'coralline-*.tmTheme' -type f | wc -l)
((remaining_themes == 0)) || fail 'uninstall left generated themes'
[ "$codex_config_hash" = "$(sha256sum "$codex_home/config.toml" | awk '{print $1}')" ] || fail 'uninstall changed config.toml'
uninstall_backup=$(find "$codex_home/coralline-codex-backups" -path '*/coralline-codex.conf' -print -quit)
assert_file "$uninstall_backup" 'uninstall recoverable config backup'
pass 'uninstall is scoped and recoverable'

printf '1..%d\n' "$passes"

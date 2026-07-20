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
python3 -c 'import pathlib,sys; [compile(pathlib.Path(p).read_text(), p, "exec") for p in sys.argv[1:]]' \
  "$ROOT/lib/config.py" "$ROOT/lib/usage.py" "$ROOT/tools/generate_themes.py"
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

usage_dir="$TEST_ROOT/usage cache"
mkdir -p "$usage_dir"
fake_codex="$usage_dir/fake codex"
cat > "$fake_codex" <<'EOF'
#!/usr/bin/env bash
while IFS= read -r line; do
  case $line in
    *'"method":"initialize"'*) printf '%s\n' '{"id":1,"result":{"userAgent":"fake"}}' ;;
    *'account/rateLimits/read'*) printf '%s\n' '{"id":2,"result":{"rateLimits":{"planType":"pro","primary":{"usedPercent":34,"windowDurationMins":10080,"resetsAt":2000000000},"secondary":null}}}' ;;
    *'account/usage/read'*) printf '%s\n' '{"id":3,"result":{"summary":{"lifetimeTokens":123456789},"dailyUsageBuckets":[]}}' ;;
  esac
done
EOF
chmod 755 "$fake_codex"
rate_cache="$usage_dir/rate limits.env"
python3 "$ROOT/lib/usage.py" fetch --codex-bin "$fake_codex" --rate-cache "$rate_cache"
rate_values=$(< "$rate_cache")
assert_contains "$rate_values" 'CORALLINE_LIMIT1_LABEL=7d' 'weekly window classified from duration'
assert_contains "$rate_values" 'CORALLINE_LIMIT1_REMAINING=66' 'remaining plan usage calculated'
assert_contains "$rate_values" 'CORALLINE_LIFETIME_TOKENS=123456789' 'account token activity cached'
pass 'official app-server rate-limit protocol and cache mapping'

rollout="$usage_dir/rollout-test.jsonl"
cat > "$rollout" <<'EOF'
{"timestamp":"2026-07-20T12:00:00Z","type":"session_meta","payload":{"id":"test","cwd":"/tmp/project"}}
{"timestamp":"2026-07-20T12:00:01Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":120000,"cached_input_tokens":80000,"output_tokens":3456,"total_tokens":123456},"last_token_usage":{"total_tokens":22000},"model_context_window":258400}}}
EOF
session_cache="$usage_dir/session tokens.env"
python3 "$ROOT/lib/usage.py" extract --rollout "$rollout" --session-cache "$session_cache"
pid_rollout=$(python3 - "$ROOT/lib/usage.py" "$rollout" <<'PY'
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import time

spec = importlib.util.spec_from_file_location("coralline_usage", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
holder = subprocess.Popen(
    [sys.executable, "-c", "import sys,time; f=open(sys.argv[1]); time.sleep(10)", sys.argv[2]]
)
try:
    time.sleep(0.2)
    found = module.rollout_from_pid(os.getpid())
    print(found or "")
finally:
    holder.terminate()
    holder.wait()
PY
)
[ "$pid_rollout" = "$rollout" ] || fail 'rollout discovery did not traverse the Codex launcher process tree'
state="$usage_dir/state.env"
printf 'CORALLINE_RATE_CACHE=%q\nCORALLINE_SESSION_CACHE=%q\n' "$rate_cache" "$session_cache" > "$state"
usage_render=$(CC_ASCII=on CC_SEGMENTS='limits tokens' CORALLINE_CODEX_CONFIG=/dev/null \
  "$ROOT/lib/render.sh" --plain --width 160 --cwd "$empty" --state "$state")
assert_contains "$usage_render" '7d ###-- 66% left' 'plan limit renders in companion bar'
assert_contains "$usage_render" 'tok 123.4k in:120.0k out:3.4k' 'session tokens render in companion bar'
pass 'rollout discovery and cached usage segments render'

priority_render=$(CC_ASCII=on CORALLINE_CODEX_CONFIG=/dev/null \
  "$ROOT/lib/render.sh" --plain --width 80 --cwd "$repo" --state "$state")
assert_contains "$priority_render" '7d ###-- 66% left' 'plan limit survives a narrow companion bar'
assert_contains "$priority_render" 'tok 123.4k in:120.0k out:3.4k' 'session tokens survive a narrow companion bar'
pass 'usage segments take priority when terminal width is constrained'

watch_home="$usage_dir/watcher home"
mkdir -p "$watch_home/sessions/2026/07/20"
cp "$rollout" "$watch_home/sessions/2026/07/20/rollout-watcher.jsonl"
watched_rate="$usage_dir/watched rate.env"
watched_session="$usage_dir/watched session.env"
python3 "$ROOT/lib/usage.py" watch --codex-bin "$fake_codex" --codex-home "$watch_home" \
  --rate-cache "$watched_rate" --session-cache "$watched_session" \
  --start-epoch 0 --cwd /tmp/project --pid $$ --interval 30 &
watcher_pid=$!
for _ in 1 2 3 4 5 6; do
  if [ -f "$watched_session" ] && rg -q 'CORALLINE_SESSION_AVAILABLE=1' "$watched_session"; then break; fi
  sleep 0.5
done
kill "$watcher_pid" >/dev/null 2>&1 || true
wait "$watcher_pid" >/dev/null 2>&1 || true
assert_contains "$(< "$watched_session")" 'CORALLINE_SESSION_TOTAL=123456' 'watcher discovers active rollout tokens'
assert_contains "$(< "$watched_rate")" 'CORALLINE_LIMIT1_REMAINING=66' 'watcher refreshes account limits'
pass 'background watcher combines account and active-session data'

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
assert_file "$codex_home/coralline-codex/lib/usage.py" 'fresh install usage watcher'
[ -L "$bin_dir/coralline-codex" ] || fail 'fresh install command symlink'
generated_count=$(find "$codex_home/themes" -name 'coralline-*.tmTheme' -type f | wc -l)
((generated_count == 9)) || fail "expected 9 generated themes, got $generated_count"
[ "$codex_config_hash" = "$(sha256sum "$codex_home/config.toml" | awk '{print $1}')" ] || fail 'install changed config.toml'
CODEX_HOME="$codex_home" CORALLINE_BIN_DIR="$bin_dir" "$bin_dir/coralline-codex" verify >/dev/null
pass 'isolated fresh install and strict Codex verification'

python3 "$codex_home/coralline-codex/lib/config.py" merge \
  --config "$codex_home/coralline-codex.conf" --backup-dir "$codex_home/coralline-codex-backups" \
  'CC_SEGMENTS=dir project git node python model profile elapsed clock' >/dev/null
printf 'local marker\n' >> "$codex_home/coralline-codex/VERSION"
CODEX_HOME="$codex_home" CORALLINE_BIN_DIR="$bin_dir" "$ROOT/install.sh" --update >/dev/null
backup_install=$(find "$codex_home/coralline-codex-backups" -path '*/install/VERSION' -print -quit)
assert_file "$backup_install" 'upgrade runtime backup'
assert_contains "$(< "$backup_install")" 'local marker' 'upgrade retained exact old runtime'
assert_not_contains "$(< "$codex_home/coralline-codex/VERSION")" 'local marker' 'upgrade installed new runtime'
assert_contains "$(< "$codex_home/coralline-codex.conf")" \
  'CC_SEGMENTS='\''limits tokens dir git project node python model profile elapsed clock'\''' \
  'upgrade migrated the previous default segment order'
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

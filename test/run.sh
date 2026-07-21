#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
CURRENT_VERSION=$(< "$ROOT/VERSION")
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/coralline-codex-tests.XXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT
passes=0
WINDOWS_SHELL=0
case $(uname -s) in MINGW* | MSYS* | CYGWIN*) WINDOWS_SHELL=1 ;; esac

pass() { printf 'ok %02d - %s\n' "$((++passes))" "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
assert_contains() { [[ $1 == *"$2"* ]] || fail "$3 (missing: $2)"; }
assert_not_contains() { [[ $1 != *"$2"* ]] || fail "$3 (unexpected: $2)"; }
assert_file() { [ -f "$1" ] || fail "$2 ($1)"; }
assert_absent() { if [ -e "$1" ] || [ -L "$1" ]; then fail "$2 ($1)"; fi; }
hash_file() { python3 - "$1" <<'PY'
from pathlib import Path
import hashlib
import sys
print(hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest())
PY
}

if [ "${CORALLINE_TEST_USE_FAKE_CODEX:-0}" = 1 ]; then
  mkdir -p "$TEST_ROOT/test-bin"
  cat > "$TEST_ROOT/test-bin/platform_codex.py" <<'PY'
import sys
import time
import os
from pathlib import Path
capture = os.environ.get("CORALLINE_TEST_CAPTURE_ARGS")
if capture:
    Path(capture).write_text("\n".join(sys.argv[1:]) + "\n", encoding="utf-8")
if "--version" in sys.argv:
    print("codex-cli platform-test")
    time.sleep(0.5)
else:
    print("fake codex: " + " ".join(sys.argv[1:]))
PY
  if ((WINDOWS_SHELL)); then
    platform_python_windows=$(cygpath -w "$TEST_ROOT/test-bin/platform_codex.py")
    cat > "$TEST_ROOT/test-bin/codex" <<EOF
#!/usr/bin/env bash
exec python "$platform_python_windows" "\$@"
EOF
    chmod 755 "$TEST_ROOT/test-bin/codex"
  else
    cat > "$TEST_ROOT/test-bin/codex" <<EOF
#!/usr/bin/env bash
exec python3 "$TEST_ROOT/test-bin/platform_codex.py" "\$@"
EOF
    chmod 755 "$TEST_ROOT/test-bin/codex"
  fi
  PATH="$TEST_ROOT/test-bin:$PATH"
  export PATH
fi

bash -n "$ROOT/bin/coralline-codex" "$ROOT/lib/render.sh" "$ROOT/configure.sh" \
  "$ROOT/install.sh" "$ROOT/test/verify-install.sh" "$0"
python3 -c 'import pathlib,sys; [compile(pathlib.Path(p).read_text(encoding="utf-8"), p, "exec") for p in sys.argv[1:]]' \
  "$ROOT/lib/config.py" "$ROOT/lib/shell_integration.py" "$ROOT/lib/usage.py" \
  "$ROOT/tools/generate_themes.py" "$ROOT/tools/render_assets.py"
python3 "$ROOT/tools/render_assets.py" --check >/dev/null
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$ROOT/bin/coralline-codex" "$ROOT/lib/render.sh" "$ROOT/configure.sh" \
    "$ROOT/install.sh" "$ROOT/test/verify-install.sh"
fi
pass 'shell and Python lint/syntax checks'

if [ "$(uname -s)" != Darwin ] && command -v tmux >/dev/null 2>&1 && command -v script >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
  printf -v tty_command '%q --version' "$ROOT/bin/coralline-codex"
  if ! tty_output=$(TERM=xterm-256color timeout 10 script -qfec "$tty_command" /dev/null 2>&1); then
    fail "tmux companion pseudo-terminal launch failed: $tty_output"
  fi
  assert_contains "$tty_output" 'codex-cli ' 'tmux companion launches Codex in a pseudo-terminal'
  assert_not_contains "$tty_output" 'unbound variable' 'tmux companion cleanup is scoped'
  pass 'isolated tmux companion launch and cleanup'

  dynamic_root="$TEST_ROOT/dynamic agent rows"
  dynamic_home="$dynamic_root/Codex Home"
  dynamic_sockets="$dynamic_root/sockets"
  mkdir -p "$dynamic_home" "$dynamic_sockets" "$dynamic_root/bin"
  cat > "$dynamic_root/bin/fake_agent_codex.py" <<'PY'
import datetime
import json
import os
from pathlib import Path
import sys
import time

if "app-server" in sys.argv:
    for line in sys.stdin:
        message = json.loads(line)
        method = message.get("method")
        if method == "initialize":
            result = {"userAgent": "agent-row-test"}
        elif method == "account/rateLimits/read":
            result = {"rateLimits": {}}
        elif method == "account/usage/read":
            result = {}
        else:
            continue
        print(json.dumps({"id": message.get("id"), "result": result}), flush=True)
    raise SystemExit(0)

home = Path(os.environ["CODEX_HOME"])
cwd = os.environ["CORALLINE_TEST_CWD"]
now = datetime.datetime.now(datetime.timezone.utc)
directory = home / "sessions" / now.strftime("%Y/%m/%d")
directory.mkdir(parents=True, exist_ok=True)
stamp = now.isoformat().replace("+00:00", "Z")
root = [
    {"timestamp": stamp, "type": "session_meta", "payload": {"id": "root", "cwd": cwd}},
    {"timestamp": stamp, "type": "event_msg", "payload": {
        "type": "collab_agent_spawn_end", "sender_thread_id": "root", "new_thread_id": "child",
        "new_agent_nickname": "scout", "new_agent_role": "explorer", "prompt": "Inspect status rows",
        "model": "gpt-test", "reasoning_effort": "high", "status": "running"
    }},
]
child_stamp = (now + datetime.timedelta(seconds=1)).isoformat().replace("+00:00", "Z")
child = [
    {"timestamp": child_stamp, "type": "session_meta", "payload": {
        "id": "child", "parent_thread_id": "root", "agent_nickname": "scout",
        "agent_role": "explorer", "cwd": cwd
    }},
    {"timestamp": child_stamp, "type": "event_msg", "payload": {"type": "task_started"}},
]
for path, events in ((directory / "rollout-root.jsonl", root), (directory / "rollout-child.jsonl", child)):
    path.write_text("".join(json.dumps(event) + "\n" for event in events), encoding="utf-8")
time.sleep(6)
PY
  cat > "$dynamic_root/bin/codex" <<EOF
#!/usr/bin/env bash
exec python3 "$dynamic_root/bin/fake_agent_codex.py" "\$@"
EOF
  chmod 755 "$dynamic_root/bin/codex"
  printf -v dynamic_command '%q' "$ROOT/bin/coralline-codex"
  TMUX_TMPDIR="$dynamic_sockets" CODEX_HOME="$dynamic_home" \
    CORALLINE_CODEX_BIN="$dynamic_root/bin/codex" CORALLINE_CODEX_CONFIG=/dev/null \
    CORALLINE_TEST_CWD="$ROOT" TERM=xterm-256color \
    timeout 12 script -qfec "$dynamic_command" /dev/null >"$dynamic_root/launch.log" 2>&1 &
  dynamic_pid=$!
  dynamic_status=
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    socket_path=$(find "$dynamic_sockets" -type s -name 'coralline-*' -print 2>/dev/null | sed -n '1p')
    if [ -n "$socket_path" ]; then
      dynamic_status=$(TMUX='' tmux -S "$socket_path" show-option -gv status 2>/dev/null || true)
      [ "$dynamic_status" = 2 ] && break
    fi
    sleep 0.5
  done
  wait "$dynamic_pid" >/dev/null 2>&1 || true
  [ "$dynamic_status" = 2 ] || fail "active agent did not expand tmux status to two rows: ${dynamic_status:-missing}"
  pass 'tmux status expands for active agents and remains isolated'
fi

while IFS=$'\t' read -r theme _; do
  [[ $theme == \#* || -z $theme ]] && continue
  output=$(CC_THEME=$theme CC_ASCII=on CORALLINE_CODEX_CONFIG=/dev/null \
    CORALLINE_START_EPOCH=$(date +%s) CORALLINE_MODEL=test-model CORALLINE_PROFILE=test \
    "$ROOT/lib/render.sh" --plain --width 240 --cwd "$ROOT")
  assert_contains "$output" 'test-model' "theme $theme renders"
done < "$ROOT/themes/palettes.tsv"
pass 'all nine themes render'

powerline=$(CC_STYLE=powerline CC_ASCII=off CC_SEGMENTS='dir clock' \
  CORALLINE_CODEX_CONFIG=/dev/null "$ROOT/lib/render.sh" --tmux --width 240 --cwd "$TEST_ROOT")
assert_contains "$powerline" '#[fg=#51a6c7,bg=#46506e,nobold]' \
  'powerline joins adjacent segment colors with a right arrow'
assert_contains "$powerline" '#[fg=#46506e,bg=#1e1f2a,nobold]#[default]' \
  'powerline closes the final segment into the companion background'
pass 'connected Powerline arrows render with continuous color transitions'

tmux_escape_cache="$TEST_ROOT/tmux escape.env"
cat > "$tmux_escape_cache" <<'EOF'
CORALLINE_AGENT_COUNT=1
CORALLINE_AGENT1_NAME=scout
CORALLINE_AGENT1_TASK='Inspect #[fg=red] formatting'
CORALLINE_AGENT1_STATUS=running
EOF
tmux_escape=$(CC_ASCII=off CORALLINE_AGENT_CACHE="$tmux_escape_cache" CORALLINE_CODEX_CONFIG=/dev/null \
  "$ROOT/lib/render.sh" --tmux --agent 1 --width 160 --cwd "$TEST_ROOT")
assert_contains "$tmux_escape" '##[fg=red]' 'agent task escapes tmux format markers'
assert_not_contains "$tmux_escape" 'Inspect #[fg=red]' 'agent task cannot inject a tmux style'
pass 'dynamic labels are escaped before entering the tmux format parser'

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
cat > "$usage_dir/fake_codex.py" <<'PY'
import json
import os
import sys
from pathlib import Path
capture = os.environ.get("CORALLINE_TEST_CAPTURE_ARGS")
if capture:
    Path(capture).write_text("\n".join(sys.argv[1:]) + "\n", encoding="utf-8")
if "--version" in sys.argv:
    print("codex-cli native-test")
    raise SystemExit(0)
for line in sys.stdin:
    message = json.loads(line)
    method = message.get("method")
    if method == "initialize":
        print(json.dumps({"id": 1, "result": {"userAgent": "fake"}}), flush=True)
    elif method == "account/rateLimits/read":
        print(json.dumps({"id": 2, "result": {"rateLimits": {"planType": "pro", "primary": {
            "usedPercent": 34, "windowDurationMins": 10080, "resetsAt": 2000000000
        }, "secondary": None}}}), flush=True)
    elif method == "account/usage/read":
        print(json.dumps({"id": 3, "result": {"summary": {"lifetimeTokens": 123456789}, "dailyUsageBuckets": []}}), flush=True)
PY
if ((WINDOWS_SHELL)); then
  fake_codex="$usage_dir/fake codex.cmd"
  usage_python_windows=$(cygpath -w "$usage_dir/fake_codex.py")
  cat > "$fake_codex" <<EOF
@echo off
python "$usage_python_windows" %*
EOF
else
  fake_codex="$usage_dir/fake codex"
  cat > "$fake_codex" <<EOF
#!/usr/bin/env bash
exec python3 "$usage_dir/fake_codex.py" "\$@"
EOF
  chmod 755 "$fake_codex"
fi
rate_cache="$usage_dir/rate limits.env"
python3 "$ROOT/lib/usage.py" fetch --codex-bin "$fake_codex" --rate-cache "$rate_cache"
rate_values=$(< "$rate_cache")
assert_contains "$rate_values" 'CORALLINE_LIMIT1_LABEL=7d' 'weekly window classified from duration'
assert_contains "$rate_values" 'CORALLINE_LIMIT1_REMAINING=66' 'remaining plan usage calculated'
assert_contains "$rate_values" 'CORALLINE_LIFETIME_TOKENS=123456789' 'account token activity cached'
assert_contains "$rate_values" "CORALLINE_RATE_ERROR=''" 'successful refresh clears prior error state'
pass 'official app-server rate-limit protocol and cache mapping'

rollout="$usage_dir/rollout-test.jsonl"
cat > "$rollout" <<'EOF'
{"timestamp":"2026-07-20T12:00:00Z","type":"session_meta","payload":{"id":"test","cwd":"/tmp/project"}}
{"timestamp":"2026-07-20T12:00:01Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":120000,"cached_input_tokens":80000,"output_tokens":3456,"total_tokens":123456},"last_token_usage":{"total_tokens":22000},"model_context_window":258400}}}
EOF
session_cache="$usage_dir/session tokens.env"
python3 "$ROOT/lib/usage.py" extract --rollout "$rollout" --session-cache "$session_cache"
incremental=$(python3 - "$ROOT/lib/usage.py" "$rollout" <<'PY'
import importlib.util
import json
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location("coralline_usage", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
path = Path(sys.argv[2])
offset, initial = module.read_rollout_updates(path)
event = {"type": "event_msg", "payload": {"type": "token_count", "info": {
    "total_token_usage": {"input_tokens": 200000, "output_tokens": 4000, "total_tokens": 204000}
}}}
with path.open("ab") as handle:
    handle.write(json.dumps(event).encode())
partial_offset, partial = module.read_rollout_updates(path, offset)
with path.open("ab") as handle:
    handle.write(b"\n")
final_offset, final = module.read_rollout_updates(path, partial_offset)
print(initial["CORALLINE_SESSION_TOTAL"], partial is None, partial_offset == offset,
      final["CORALLINE_SESSION_TOTAL"], final_offset > offset)
PY
)
[ "$incremental" = '123456 True True 204000 True' ] || fail 'incremental rollout tailing mishandled a partial JSONL record'
if ((WINDOWS_SHELL == 0)) && [ "$(uname -s)" = Linux ]; then
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
fi
state="$usage_dir/state.env"
printf 'CORALLINE_RATE_CACHE=%q\nCORALLINE_SESSION_CACHE=%q\n' "$rate_cache" "$session_cache" > "$state"
usage_render=$(CC_ASCII=on CC_SEGMENTS='limits tokens' CORALLINE_CODEX_CONFIG=/dev/null \
  "$ROOT/lib/render.sh" --plain --width 160 --cwd "$empty" --state "$state")
assert_contains "$usage_render" '7d ###-- 66% left' 'plan limit renders in companion bar'
assert_contains "$usage_render" 'tok 123.4k in:120.0k out:3.4k' 'session tokens render in companion bar'
pass 'rollout discovery and cached usage segments render'

context_render=$(CC_ASCII=on CC_SEGMENTS='context reasoning' CORALLINE_CODEX_CONFIG=/dev/null \
  CORALLINE_CONTEXT_USED=42000 CORALLINE_CONTEXT_WINDOW=200000 CORALLINE_REASONING=high \
  "$ROOT/lib/render.sh" --plain --width 120 --cwd "$empty")
assert_contains "$context_render" 'ctx #---- 21% 42.0k' 'current context usage renders from Codex token telemetry'
assert_contains "$context_render" 'reason high' 'effective reasoning effort renders'
pass 'Codex context and reasoning segments use authoritative session state'

python3 - "$ROOT/lib/usage.py" "$rate_cache" <<'PY'
import importlib.util
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location("coralline_usage", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
cache = Path(sys.argv[2])
module.record_rate_failure(cache, RuntimeError("temporary app-server failure"))
values = module.read_env(cache)
assert values["CORALLINE_LIMIT1_REMAINING"] == "66"
assert values["CORALLINE_RATE_ERROR"] == "temporary app-server failure"
PY
stale_cache="$usage_dir/stale rate.env"
sed 's/^CORALLINE_RATE_UPDATED=.*/CORALLINE_RATE_UPDATED=1/' "$rate_cache" > "$stale_cache"
stale_render=$(CC_ASCII=on CC_USAGE_STALE_AFTER=60 CC_SEGMENTS='limits' \
  CORALLINE_RATE_CACHE="$stale_cache" CORALLINE_CODEX_CONFIG=/dev/null \
  "$ROOT/lib/render.sh" --plain --width 120 --cwd "$empty")
assert_contains "$stale_render" 'stale:' 'stale plan snapshot is visibly marked'
pass 'refresh failures preserve data and stale snapshots remain honest'

burn_history="$usage_dir/usage history.json"
burn_cache="$usage_dir/burn rate.env"
python3 - "$ROOT/lib/usage.py" "$burn_history" "$burn_cache" <<'PY'
import importlib.util
import json
import os
from pathlib import Path
import stat
import sys

spec = importlib.util.spec_from_file_location("coralline_usage", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
history = Path(sys.argv[2])
cache = Path(sys.argv[3])
values = {
    "CORALLINE_RATE_AVAILABLE": 1,
    "CORALLINE_LIMIT_COUNT": 2,
    "CORALLINE_LIMIT1_LABEL": "7d",
    "CORALLINE_LIMIT1_USED": 10,
    "CORALLINE_LIMIT1_REMAINING": 90,
    "CORALLINE_LIMIT1_RESET": 200000,
    "CORALLINE_LIMIT1_WINDOW_MINS": 10080,
    "CORALLINE_LIMIT2_LABEL": "5h",
    "CORALLINE_LIMIT2_USED": 10,
    "CORALLINE_LIMIT2_REMAINING": 90,
    "CORALLINE_LIMIT2_RESET": 10000,
    "CORALLINE_LIMIT2_WINDOW_MINS": 300,
}
module.apply_burn_metrics(values, history, now=1000)
assert values["CORALLINE_LIMIT1_BURN_STATE"] == "warming"
values["CORALLINE_LIMIT1_USED"] = 20
values["CORALLINE_LIMIT1_REMAINING"] = 80
values["CORALLINE_LIMIT2_USED"] = 11
values["CORALLINE_LIMIT2_REMAINING"] = 89
module.apply_burn_metrics(values, history, now=4600)
assert values["CORALLINE_LIMIT1_BURN_STATE"] == "tracking"
assert values["CORALLINE_LIMIT1_BURN_ETA"] == 28800
assert values["CORALLINE_LIMIT1_BURN_RATE_PER_HOUR"] == 10
assert values["CORALLINE_LIMIT2_BURN_STATE"] == "safe"
assert not history.with_name(f".{history.name}.lock").exists()
if os.name != "nt":
    assert stat.S_IMODE(history.stat().st_mode) == 0o600
assert len(json.loads(history.read_text())["windows"]) == 2
module.atomic_env(cache, values)
PY
burn_render=$(CC_ASCII=on CC_SEGMENTS='burn' CORALLINE_RATE_CACHE="$burn_cache" \
  CORALLINE_CODEX_CONFIG=/dev/null "$ROOT/lib/render.sh" --plain --width 120 --cwd "$empty")
assert_contains "$burn_render" 'burn 7d 8h00m' 'projection shows time to exhaustion when current burn outruns reset'
assert_contains "$burn_render" 'burn 5h reset-safe' 'projection distinguishes usage likely to survive reset'
pass 'burn-rate history produces conservative, deterministic quota projections'

priority_render=$(CC_ASCII=on CORALLINE_CODEX_CONFIG=/dev/null \
  "$ROOT/lib/render.sh" --plain --width 80 --cwd "$repo" --state "$state")
assert_contains "$priority_render" '7d ###-- 66% left' 'plan limit survives a narrow companion bar'
assert_contains "$priority_render" 'tok 123.4k in:120.0k out:3.4k' 'session tokens survive a narrow companion bar'
pass 'usage segments take priority when terminal width is constrained'

compact_render=$(CC_ASCII=on CORALLINE_CODEX_CONFIG=/dev/null \
  "$ROOT/lib/render.sh" --plain --width 30 --cwd "$repo" --state "$state")
assert_contains "$compact_render" '7d 66%' 'quota compacts instead of disappearing at 30 columns'
assert_contains "$compact_render" 'tok 123.4k' 'session tokens compact instead of disappearing at 30 columns'
compact_width=$(python3 -c 'import sys; print(len(sys.stdin.read().rstrip("\n")))' <<< "$compact_render")
((compact_width <= 30)) || fail "compact usage exceeded width: $compact_width"
pass 'critical usage data adapts down to a 30-column terminal'

watch_home="$usage_dir/watcher home"
mkdir -p "$watch_home/sessions/2026/07/20"
cp "$rollout" "$watch_home/sessions/2026/07/20/rollout-watcher.jsonl"
watch_cwd="$TEST_ROOT/watcher project"
mkdir -p "$watch_cwd"
python3 - "$watch_home/sessions/2026/07/20/rollout-watcher.jsonl" "$watch_cwd" <<'PY'
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines()
first = json.loads(lines[0])
first["payload"]["cwd"] = sys.argv[2]
lines[0] = json.dumps(first, separators=(",", ":"))
path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
watched_rate="$usage_dir/watched rate.env"
watched_session="$usage_dir/watched session.env"
watched_agents="$usage_dir/watched agents.env"
cat >> "$watch_home/sessions/2026/07/20/rollout-watcher.jsonl" <<'EOF'
{"timestamp":"2026-07-20T12:00:02Z","type":"event_msg","payload":{"type":"collab_agent_spawn_end","sender_thread_id":"test","new_thread_id":"child-1","new_agent_nickname":"scout","new_agent_role":"explorer","prompt":"Explore config sources","model":"gpt-5.4","reasoning_effort":"high","status":"running","completed_at_ms":1784548802000}}
EOF
cat > "$watch_home/sessions/2026/07/20/rollout-child.jsonl" <<EOF
{"timestamp":"2026-07-20T12:00:02Z","type":"session_meta","payload":{"id":"child-1","parent_thread_id":"test","agent_nickname":"scout","agent_role":"explorer","agent_path":"scout","cwd":"$watch_cwd"}}
{"timestamp":"2026-07-20T12:00:03Z","type":"turn_context","payload":{"model":"gpt-5.4","effort":"high"}}
{"timestamp":"2026-07-20T12:00:03Z","type":"event_msg","payload":{"type":"task_started"}}
{"timestamp":"2026-07-20T12:00:04Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":42000},"last_token_usage":{"total_tokens":42000},"model_context_window":200000}}}
EOF
python3 "$ROOT/lib/usage.py" watch --codex-bin "$fake_codex" --codex-home "$watch_home" \
  --rate-cache "$watched_rate" --session-cache "$watched_session" \
  --agent-cache "$watched_agents" --agent-rows 3 \
  --start-epoch 0 --cwd "$watch_cwd" --pid $$ --interval 30 &
watcher_pid=$!
for _ in 1 2 3 4 5 6; do
  if [ -f "$watched_session" ] && [ -f "$watched_agents" ] && \
    grep -q 'CORALLINE_SESSION_AVAILABLE=1' "$watched_session" && \
    grep -q 'CORALLINE_AGENT_COUNT=1' "$watched_agents"; then break; fi
  sleep 0.5
done
kill "$watcher_pid" >/dev/null 2>&1 || true
wait "$watcher_pid" >/dev/null 2>&1 || true
assert_contains "$(< "$watched_session")" 'CORALLINE_SESSION_TOTAL=204000' 'watcher discovers the latest active rollout tokens'
assert_contains "$(< "$watched_rate")" 'CORALLINE_LIMIT1_REMAINING=66' 'watcher refreshes account limits'
agent_values=$(< "$watched_agents")
assert_contains "$agent_values" 'CORALLINE_AGENT1_NAME=scout' 'watcher maps the Codex agent nickname'
assert_contains "$agent_values" 'CORALLINE_AGENT1_ROLE=explorer' 'watcher maps the Codex agent role'
assert_contains "$agent_values" "CORALLINE_AGENT1_TASK='Explore config sources'" 'watcher maps the spawn task'
assert_contains "$agent_values" 'CORALLINE_AGENT1_MODEL=gpt-5.4' 'watcher maps the effective agent model'
assert_contains "$agent_values" 'CORALLINE_AGENT1_CONTEXT_USED=42000' 'watcher maps per-agent context use'
agent_render=$(CC_ASCII=off CORALLINE_AGENT_CACHE="$watched_agents" CORALLINE_CODEX_CONFIG=/dev/null \
  "$ROOT/lib/render.sh" --plain --agent 1 --width 180 --cwd "$watch_cwd")
assert_contains "$agent_render" '● scout [explorer]' 'active agent identity renders'
assert_contains "$agent_render" '◆ gpt-5.4 high' 'active agent model and reasoning render'
assert_contains "$agent_render" '⬡ ▰▱▱▱▱ 21% 42.0k' 'active agent context gauge renders'
pass 'background watcher combines account, session, and authoritative subagent data'

agent_lifecycle=$(python3 - "$ROOT/lib/usage.py" <<'PY'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("coralline_usage", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert module.display_text("safe\x1b[31m red") == "safe red"
message_state = {"agent_path": "/root/scout"}
module.apply_agent_event({
    "type": "response_item",
    "payload": {"type": "agent_message", "author": "/root", "recipient": "/root/scout",
                "content": [{"type": "input_text", "text": "Inspect the status implementation"}]},
}, message_state, {}, {})
assert message_state["task"] == "Inspect the status implementation"
states = {
    "root": {"parent_id": "", "status": "running"},
    "child": {"parent_id": "root", "name": "scout", "status": "running", "created_epoch": 1},
    "nested": {"parent_id": "child", "name": "worker", "status": "running", "created_epoch": 2},
    "done": {"parent_id": "root", "name": "done", "status": "completed", "created_epoch": 3},
}
values = module.agent_cache_values("root", states, {}, {}, 1)
print(values["CORALLINE_AGENT_COUNT"], values["CORALLINE_AGENT_TOTAL_ACTIVE"],
      values["CORALLINE_AGENT1_DESCENDANTS"], values["CORALLINE_AGENT1_OVERFLOW"])
states["child"]["status"] = "completed"
states["nested"]["status"] = "completed"
collapsed = module.agent_cache_values("root", states, {}, {}, 3)
print(collapsed["CORALLINE_AGENT_COUNT"])
PY
)
[ "$agent_lifecycle" = $'1 2 1 1\n0' ] || fail 'agent rows did not aggregate overflow and collapse completed work'
pass 'nested agent overflow is explicit and completed rows collapse cleanly'

config_dir="$TEST_ROOT/config merge"
mkdir -p "$config_dir/backups"
config="$config_dir/custom config.conf"
cat > "$config" <<'EOF'
# user comment
CC_THEME=mono
CUSTOM_KEEP='value with spaces'
CC_NODE=off
EOF
before=$(hash_file "$config")
python3 "$ROOT/lib/config.py" merge --config "$config" --backup-dir "$config_dir/backups" \
  CC_THEME=nord CC_NODE=on >/dev/null
merged=$(< "$config")
assert_contains "$merged" '# user comment' 'config comments preserved'
assert_contains "$merged" "CUSTOM_KEEP='value with spaces'" 'unknown config preserved'
assert_contains "$merged" 'CC_THEME=nord' 'known config replaced'
backup=$(find "$config_dir/backups" -type f -name 'custom config.conf.bak.*' -print | sed -n '1p')
assert_file "$backup" 'config backup created'
after_backup=$(hash_file "$backup")
[ "$before" = "$after_backup" ] || fail 'config backup is not byte-identical'
pass 'configuration merging preserves unrelated data and backs up first'

wizard_home="$TEST_ROOT/wizard home"
mkdir -p "$wizard_home"
wizard_output=$(printf '2\nclassic\n2\n1\n30\n60\nn\ny\n' | \
  TERM=xterm-256color CODEX_HOME="$wizard_home" "$ROOT/configure.sh" --wizard)
wizard_config=$(< "$wizard_home/coralline-codex.conf")
assert_contains "$wizard_config" 'CC_THEME=catppuccin-mocha' 'wizard saved selected theme'
assert_contains "$wizard_config" 'CC_STYLE=classic' 'wizard saved classic style'
assert_contains "$wizard_config" 'CC_ASCII=on' 'wizard saved ASCII compatibility mode'
assert_contains "$wizard_config" "CC_SEGMENTS='limits tokens dir git elapsed clock'" 'wizard saved focused layout'
assert_contains "$wizard_config" 'CC_USAGE_REFRESH=30' 'wizard saved usage refresh interval'
assert_contains "$wizard_config" 'CC_USAGE_STALE_AFTER=60' 'wizard saved stale threshold'
assert_contains "$wizard_config" 'CC_AGENTS=on' 'wizard preserved active agent rows'
assert_contains "$wizard_config" 'CC_AGENT_ROWS=3' 'wizard preserved the agent row cap'
assert_contains "$wizard_output" 'Final preview:' 'wizard rendered a final visual preview'
configured_preview=$(TERM=xterm-256color CODEX_HOME="$wizard_home" "$ROOT/configure.sh" --preview)
assert_contains "$configured_preview" '7d ' 'configured preview contains realistic quota data'
assert_contains "$configured_preview" 'tok 12.4k' 'configured preview contains realistic token data'
if CODEX_HOME="$wizard_home" "$ROOT/configure.sh" --segments 'limits invented' >/dev/null 2>&1; then
  fail 'configure accepted an unknown segment'
fi
pass 'visual wizard previews, validates, and persists a complete setup'

native_home="$TEST_ROOT/native footer"
mkdir -p "$native_home"
native_config="$native_home/coralline-codex.conf"
cat > "$native_config" <<'EOF'
CC_THEME=claude-coral
CC_NATIVE_STATUS=on
CC_NATIVE_FIELDS='model-with-reasoning run-state task-progress'
EOF
native_capture="$native_home/args.txt"
CORALLINE_CODEX_BIN="$fake_codex" CORALLINE_CODEX_CONFIG="$native_config" \
  CORALLINE_TEST_CAPTURE_ARGS="$native_capture" CODEX_HOME="$native_home" \
  "$ROOT/bin/coralline-codex" --no-companion --version >/dev/null
native_args=$(< "$native_capture")
assert_contains "$native_args" 'tui.status_line=["model-with-reasoning","run-state","task-progress"]' \
  'native footer fields are passed as a scoped Codex override'
python3 "$ROOT/lib/config.py" merge --config "$native_config" --backup-dir "$native_home/backups" \
  CC_NATIVE_FIELDS=inherit >/dev/null
CORALLINE_CODEX_BIN="$fake_codex" CORALLINE_CODEX_CONFIG="$native_config" \
  CORALLINE_TEST_CAPTURE_ARGS="$native_capture" CODEX_HOME="$native_home" \
  "$ROOT/bin/coralline-codex" --no-companion --version >/dev/null
assert_not_contains "$(< "$native_capture")" 'tui.status_line=' 'inherit preserves the user native footer layout'
if CORALLINE_CODEX_CONFIG="$native_config" CODEX_HOME="$native_home" \
  "$ROOT/configure.sh" --native-fields 'model invented' >/dev/null 2>&1; then
  fail 'configure accepted an unknown native footer field'
fi
pass 'native footer coverage is configurable, validated, and non-destructive'

shell_dir="$TEST_ROOT/shell integration"
mkdir -p "$shell_dir/backups"
shell_rc="$shell_dir/bash rc"
shell_state_home="$shell_dir/Codex Home"
shell_wrapper="$shell_dir/coralline wrapper"
shell_codex="$shell_dir/real codex"
cat > "$shell_wrapper" <<'EOF'
#!/usr/bin/env bash
printf 'wrapper:%s:%s\n' "$CORALLINE_CODEX_BIN" "$*"
EOF
cat > "$shell_codex" <<'EOF'
#!/usr/bin/env bash
printf 'real:%s\n' "$*"
EOF
chmod 755 "$shell_wrapper" "$shell_codex"
cat > "$shell_rc" <<'EOF'
export USER_SETTING='keep me'
# coralline-codex: route normal Codex launches through the themed wrapper.
codex() {
    CORALLINE_CODEX_BIN=/usr/bin/codex "$HOME/.local/bin/coralline-codex" "$@"
}
EOF
python3 "$ROOT/lib/shell_integration.py" install --codex-home "$shell_state_home" \
  --backup-dir "$shell_dir/backups" --shell bash --rc "$shell_rc" \
  --wrapper "$shell_wrapper" --codex-bin "$shell_codex" >/dev/null
hook=$(< "$shell_rc")
assert_contains "$hook" '# >>> coralline-codex managed shell integration >>>' 'managed shell marker installed'
assert_not_contains "$hook" '# coralline-codex: route normal' 'legacy shell hook migrated'
assert_contains "$hook" "export USER_SETTING='keep me'" 'unrelated shell configuration preserved'
hook_hash=$(hash_file "$shell_rc")
python3 "$ROOT/lib/shell_integration.py" install --codex-home "$shell_state_home" \
  --backup-dir "$shell_dir/backups" --shell bash --rc "$shell_rc" \
  --wrapper "$shell_wrapper" --codex-bin "$shell_codex" >/dev/null
[ "$hook_hash" = "$(hash_file "$shell_rc")" ] || fail 'shell hook installation is not idempotent'
hook_run=$(bash -c 'source "$1"; codex --yolo' _ "$shell_rc")
shell_codex_resolved=$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve())' "$shell_codex")
assert_contains "$hook_run" "wrapper:$shell_codex_resolved:--yolo" 'managed hook routes codex through wrapper'
bypass_run=$(CORALLINE_CODEX_DISABLE=1 bash -c 'source "$1"; codex --version' _ "$shell_rc")
assert_contains "$bypass_run" 'real:--version' 'managed hook supports an explicit bypass'
python3 "$ROOT/lib/shell_integration.py" status --codex-home "$shell_state_home" \
  --backup-dir "$shell_dir/backups" --rc "$shell_rc" >/dev/null
python3 "$ROOT/lib/shell_integration.py" uninstall --codex-home "$shell_state_home" \
  --backup-dir "$shell_dir/backups" --rc "$shell_rc" >/dev/null
assert_not_contains "$(< "$shell_rc")" 'coralline-codex managed shell integration' 'managed hook removed cleanly'
assert_contains "$(< "$shell_rc")" "export USER_SETTING='keep me'" 'shell uninstall preserved unrelated configuration'
assert_absent "$shell_state_home/coralline-codex-shell.json" 'shell integration state removed'
pass 'optional shell integration is managed, reversible, and idempotent'

codex_home="$TEST_ROOT/Codex Home"
bin_dir="$TEST_ROOT/bin with spaces"
test_home="$TEST_ROOT/test home"
mkdir -p "$codex_home" "$bin_dir" "$test_home"
cat > "$codex_home/config.toml" <<'EOF'
model = "gpt-5.6"
approval_policy = "never"

[mcp_servers.example]
command = "printf"
args = ["path with spaces"]
EOF
codex_config_hash=$(hash_file "$codex_home/config.toml")
HOME="$test_home" CODEX_HOME="$codex_home" CORALLINE_BIN_DIR="$bin_dir" \
  "$ROOT/install.sh" --shell-hook bash >/dev/null
assert_file "$codex_home/coralline-codex/VERSION" 'fresh install runtime'
assert_file "$codex_home/coralline-codex/assets/hero.svg" 'fresh install README visual'
assert_file "$codex_home/coralline-codex/lib/usage.py" 'fresh install usage watcher'
assert_file "$codex_home/coralline-codex/lib/shell_integration.py" 'fresh install shell integration helper'
assert_contains "$(< "$codex_home/coralline-codex.conf")" 'CC_AGENTS=on' 'fresh install enables Codex agent rows'
assert_contains "$(< "$codex_home/coralline-codex.conf")" 'CC_AGENT_ROWS=3' 'fresh install caps agent rows safely'
assert_contains "$(< "$codex_home/coralline-codex.conf")" 'task-progress' 'fresh install enables richer native footer coverage'
if ((WINDOWS_SHELL)); then
  assert_file "$bin_dir/coralline-codex" 'fresh install Git Bash command shim'
  assert_contains "$(< "$bin_dir/coralline-codex")" 'coralline-codex managed Git Bash shim' 'Git Bash command shim is identifiable'
else
  [ -L "$bin_dir/coralline-codex" ] || fail 'fresh install command symlink'
fi
assert_contains "$(< "$test_home/.bashrc")" '# >>> coralline-codex managed shell integration >>>' 'installer enables requested shell hook'
generated_count=$(find "$codex_home/themes" -name 'coralline-*.tmTheme' -type f | wc -l)
((generated_count == 9)) || fail "expected 9 generated themes, got $generated_count"
[ "$codex_config_hash" = "$(hash_file "$codex_home/config.toml")" ] || fail 'install changed config.toml'
CODEX_HOME="$codex_home" CORALLINE_BIN_DIR="$bin_dir" "$bin_dir/coralline-codex" verify >/dev/null
pass 'isolated fresh install and strict Codex verification'

python3 "$codex_home/coralline-codex/lib/config.py" merge \
  --config "$codex_home/coralline-codex.conf" --backup-dir "$codex_home/coralline-codex-backups" \
  'CC_SEGMENTS=dir project git node python model profile elapsed clock' >/dev/null
printf '0.1.0\nlocal marker\n' > "$codex_home/coralline-codex/VERSION"
upgrade_output=$(CODEX_HOME="$codex_home" CORALLINE_BIN_DIR="$bin_dir" "$ROOT/install.sh" --update)
backup_install=$(find "$codex_home/coralline-codex-backups" -path '*/install/VERSION' -print | sed -n '1p')
assert_file "$backup_install" 'upgrade runtime backup'
assert_contains "$(< "$backup_install")" 'local marker' 'upgrade retained exact old runtime'
assert_not_contains "$(< "$codex_home/coralline-codex/VERSION")" 'local marker' 'upgrade installed new runtime'
assert_contains "$upgrade_output" "Updated 0.1.0 -> $CURRENT_VERSION" 'upgrade reports the version transition'
assert_contains "$upgrade_output" 'New in this release:' 'upgrade prints release highlights'
assert_contains "$(< "$codex_home/coralline-codex.conf")" \
  'CC_SEGMENTS='\''limits burn tokens context dir git stash project node python model reasoning profile elapsed clock'\''' \
  'upgrade migrated the previous default segment order'
[ "$codex_config_hash" = "$(hash_file "$codex_home/config.toml")" ] || fail 'upgrade changed config.toml'
pass 'upgrade replaces owned runtime and preserves Codex configuration'

HOME="$test_home" CODEX_HOME="$codex_home" CORALLINE_BIN_DIR="$bin_dir" \
  "$bin_dir/coralline-codex" uninstall >/dev/null
assert_absent "$codex_home/coralline-codex" 'uninstall runtime removal'
assert_absent "$bin_dir/coralline-codex" 'uninstall command removal'
assert_absent "$codex_home/coralline-codex.conf" 'uninstall config removal'
assert_not_contains "$(< "$test_home/.bashrc")" 'coralline-codex managed shell integration' 'uninstall removed managed shell hook'
remaining_themes=$(find "$codex_home/themes" -name 'coralline-*.tmTheme' -type f | wc -l)
((remaining_themes == 0)) || fail 'uninstall left generated themes'
[ "$codex_config_hash" = "$(hash_file "$codex_home/config.toml")" ] || fail 'uninstall changed config.toml'
uninstall_backup=$(find "$codex_home/coralline-codex-backups" -path '*/coralline-codex.conf' -print | sed -n '1p')
assert_file "$uninstall_backup" 'uninstall recoverable config backup'
pass 'uninstall is scoped and recoverable'

printf '1..%d\n' "$passes"

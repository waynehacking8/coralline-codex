#!/usr/bin/env python3
"""Install and remove the optional Coralline Codex shell hook safely."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import tempfile
import time

START = "# >>> coralline-codex managed shell integration >>>"
END = "# <<< coralline-codex managed shell integration <<<"
LEGACY = re.compile(
    r"(?:^|\n)# coralline-codex: route normal Codex launches through the themed wrapper\.\n"
    r"codex\(\) \{\n"
    r"[ \t]+CORALLINE_CODEX_BIN=/usr/bin/codex \"\$HOME/\.local/bin/coralline-codex\" \"\$@\"\n"
    r"\}\n?",
    re.MULTILINE,
)


def state_path(codex_home: Path) -> Path:
    return codex_home / "coralline-codex-shell.json"


def default_shell(requested: str) -> str:
    if requested != "auto":
        return requested
    detected = Path(os.environ.get("SHELL", "")).name
    if detected in {"bash", "zsh"}:
        return detected
    raise ValueError("could not detect Bash or Zsh; pass --shell bash or --shell zsh")


def default_rc(shell: str) -> Path:
    return Path.home() / (".bashrc" if shell == "bash" else ".zshrc")


def managed_span(text: str) -> tuple[int, int] | None:
    start = text.find(START)
    if start < 0:
        return None
    end = text.find(END, start)
    if end < 0:
        raise ValueError(f"found {START!r} without its closing marker")
    end += len(END)
    if end < len(text) and text[end] == "\n":
        end += 1
    return start, end


def without_hook(text: str) -> tuple[str, bool]:
    changed = False
    span = managed_span(text)
    if span:
        text = text[: span[0]] + text[span[1] :]
        changed = True
    legacy = LEGACY.sub("\n", text)
    if legacy != text:
        text = legacy
        changed = True
    text = re.sub(r"\n{3,}", "\n\n", text).strip("\n")
    if text:
        text += "\n"
    return text, changed


def hook_block(wrapper: Path, codex_bin: Path) -> str:
    wrapper_q = shlex.quote(str(wrapper))
    codex_q = shlex.quote(str(codex_bin))
    return (
        f"{START}\n"
        "codex() {\n"
        "  if [ \"${CORALLINE_CODEX_DISABLE:-0}\" = 1 ]; then\n"
        f"    command {codex_q} \"$@\"\n"
        "  else\n"
        f"    CORALLINE_CODEX_BIN={codex_q} {wrapper_q} \"$@\"\n"
        "  fi\n"
        "}\n"
        f"{END}\n"
    )


def backup(path: Path, backup_root: Path) -> Path | None:
    if not path.exists():
        return None
    backup_root.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    candidate = backup_root / f"{path.name}.bak.{stamp}"
    counter = 1
    while candidate.exists():
        candidate = backup_root / f"{path.name}.bak.{stamp}.{counter}"
        counter += 1
    candidate.write_bytes(path.read_bytes())
    return candidate


def atomic_text(path: Path, text: str, mode: int | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.chmod(temporary, mode if mode is not None else 0o600)
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def save_state(codex_home: Path, shell: str, rc: Path) -> None:
    path = state_path(codex_home)
    atomic_text(path, json.dumps({"version": 1, "shell": shell, "rc": str(rc)}, indent=2) + "\n")


def load_state(codex_home: Path) -> dict:
    try:
        value = json.loads(state_path(codex_home).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def install(args: argparse.Namespace) -> int:
    shell = default_shell(args.shell)
    rc = args.rc or default_rc(shell)
    wrapper = args.wrapper.resolve()
    codex_bin = args.codex_bin.resolve()
    if wrapper == codex_bin:
        raise ValueError("wrapper and real Codex binary resolve to the same path")
    if not wrapper.exists() or not os.access(wrapper, os.X_OK):
        raise ValueError(f"wrapper is not executable: {wrapper}")
    if not codex_bin.exists() or not os.access(codex_bin, os.X_OK):
        raise ValueError(f"Codex binary is not executable: {codex_bin}")
    old = rc.read_text(encoding="utf-8") if rc.exists() else ""
    clean, _ = without_hook(old)
    if clean and not clean.endswith("\n"):
        clean += "\n"
    new = clean + ("\n" if clean else "") + hook_block(wrapper, codex_bin)
    saved = None
    if new != old:
        saved = backup(rc, args.backup_dir)
        mode = rc.stat().st_mode & 0o777 if rc.exists() else 0o644
        atomic_text(rc, new, mode)
    save_state(args.codex_home, shell, rc)
    print(f"Managed {shell} hook installed in {rc}")
    print(f"Real Codex binary: {codex_bin}")
    print(f"Backup: {saved or 'none (file was unchanged or newly created)'}")
    print(f"Restart your shell or run: source {shlex.quote(str(rc))}")
    return 0


def uninstall(args: argparse.Namespace) -> int:
    state = load_state(args.codex_home)
    shell = args.shell if args.shell != "auto" else str(state.get("shell") or "auto")
    if args.rc:
        rc = args.rc
    elif state.get("rc"):
        rc = Path(str(state["rc"]))
    else:
        try:
            rc = default_rc(default_shell(shell))
        except ValueError:
            print("No managed shell hook is recorded.")
            return 0
    if not rc.exists():
        print(f"No shell hook found; {rc} does not exist.")
    else:
        old = rc.read_text(encoding="utf-8")
        new, changed = without_hook(old)
        if changed:
            saved = backup(rc, args.backup_dir)
            atomic_text(rc, new, rc.stat().st_mode & 0o777)
            print(f"Managed shell hook removed from {rc}")
            print(f"Backup: {saved}")
        else:
            print(f"No managed shell hook found in {rc}")
    state_file = state_path(args.codex_home)
    if state_file.exists():
        state_file.unlink()
    return 0


def status(args: argparse.Namespace) -> int:
    state = load_state(args.codex_home)
    rc = args.rc or (Path(str(state["rc"])) if state.get("rc") else None)
    if not rc or not rc.exists():
        print("Shell integration: not installed")
        return 1
    text = rc.read_text(encoding="utf-8")
    if managed_span(text):
        print("Shell integration: installed")
        print(f"Shell: {state.get('shell') or 'unknown'}")
        print(f"RC file: {rc}")
        return 0
    print("Shell integration: not installed")
    return 1


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("install", "uninstall", "status"):
        command = sub.add_parser(name)
        command.add_argument("--codex-home", required=True, type=Path)
        command.add_argument("--backup-dir", required=True, type=Path)
        command.add_argument("--shell", choices=("auto", "bash", "zsh"), default="auto")
        command.add_argument("--rc", type=Path)
        if name == "install":
            command.add_argument("--wrapper", required=True, type=Path)
            command.add_argument("--codex-bin", required=True, type=Path)
    args = parser.parse_args()
    if args.command == "install":
        return install(args)
    if args.command == "uninstall":
        return uninstall(args)
    return status(args)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as error:
        print(f"coralline-codex shell: {error}", file=os.sys.stderr)
        raise SystemExit(2)

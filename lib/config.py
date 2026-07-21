#!/usr/bin/env python3
"""Small, dependency-free helpers for Coralline Codex configuration."""

from __future__ import annotations

import argparse
import ast
import json
import os
from pathlib import Path
import re
import shlex
import sys
import time
try:
    import tomllib
    TOMLDecodeError = tomllib.TOMLDecodeError
except ModuleNotFoundError:  # Python 3.10 and older
    tomllib = None  # type: ignore[assignment]

    class TOMLDecodeError(Exception):
        pass

ALLOWED = {
    "CC_THEME",
    "CC_STYLE",
    "CC_ASCII",
    "CC_SEGMENTS",
    "CC_NODE",
    "CC_PYTHON",
    "CC_RUNTIME_PROBE",
    "CC_MAX_DIR",
    "CC_NATIVE_STATUS",
    "CC_NATIVE_FIELDS",
    "CC_AGENTS",
    "CC_AGENT_ROWS",
    "CC_USAGE_REFRESH",
    "CC_USAGE_STALE_AFTER",
}


def backup(path: Path, backup_root: Path) -> Path | None:
    if not path.exists():
        return None
    stamp = time.strftime("%Y%m%d-%H%M%S")
    backup_root.mkdir(parents=True, exist_ok=True)
    candidate = backup_root / f"{path.name}.bak.{stamp}"
    counter = 1
    while candidate.exists():
        candidate = backup_root / f"{path.name}.bak.{stamp}.{counter}"
        counter += 1
    candidate.write_bytes(path.read_bytes())
    return candidate


def shell_assignment(key: str, value: str) -> str:
    return f"{key}={shlex.quote(value)}"


def merge_config(path: Path, changes: dict[str, str], backup_root: Path) -> Path | None:
    unknown = set(changes) - ALLOWED
    if unknown:
        raise ValueError(f"unsupported configuration key(s): {', '.join(sorted(unknown))}")
    old = path.read_text(encoding="utf-8") if path.exists() else ""
    saved = backup(path, backup_root)
    pending = dict(changes)
    output: list[str] = []
    assignment = re.compile(r"^([A-Z][A-Z0-9_]*)=")
    for line in old.splitlines():
        match = assignment.match(line)
        if match and match.group(1) in pending:
            key = match.group(1)
            output.append(shell_assignment(key, pending.pop(key)))
        else:
            output.append(line)
    if pending and output and output[-1] != "":
        output.append("")
    for key in sorted(pending):
        output.append(shell_assignment(key, pending[key]))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(output).rstrip() + "\n", encoding="utf-8")
    return saved


def read_toml(path: Path) -> dict:
    if not path.exists():
        return {}
    if tomllib is not None:
        with path.open("rb") as handle:
            return tomllib.load(handle)
    # Python <3.11 fallback: only the two documented root string keys used by
    # this renderer are needed. Stop at the first table so a nested `model`
    # cannot be mistaken for the active top-level model.
    values: dict[str, str] = {}
    wanted = {"model", "model_reasoning_effort"}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith("["):
            break
        match = re.match(r"^(model|model_reasoning_effort)\s*=\s*(.+?)\s*$", line)
        if not match or match.group(1) not in wanted:
            continue
        try:
            value = ast.literal_eval(match.group(2))
        except (SyntaxError, ValueError):
            continue
        if isinstance(value, str):
            values[match.group(1)] = value
    return values


def effective(codex_home: Path, argv: list[str]) -> dict[str, str]:
    profile = ""
    model_arg = ""
    index = 0
    while index < len(argv):
        arg = argv[index]
        if arg in {"-p", "--profile"} and index + 1 < len(argv):
            profile = argv[index + 1]
            index += 2
            continue
        if arg.startswith("--profile="):
            profile = arg.split("=", 1)[1]
        elif arg in {"-m", "--model"} and index + 1 < len(argv):
            model_arg = argv[index + 1]
            index += 2
            continue
        elif arg.startswith("--model="):
            model_arg = arg.split("=", 1)[1]
        index += 1

    base = read_toml(codex_home / "config.toml")
    layered = dict(base)
    if profile:
        layered.update(read_toml(codex_home / f"{profile}.config.toml"))
    return {
        "model": model_arg or str(layered.get("model", "auto")),
        "reasoning": str(layered.get("model_reasoning_effort", "auto")),
        "profile": profile or "default",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    merge = sub.add_parser("merge")
    merge.add_argument("--config", required=True, type=Path)
    merge.add_argument("--backup-dir", required=True, type=Path)
    merge.add_argument("assignments", nargs="+")
    eff = sub.add_parser("effective")
    eff.add_argument("--codex-home", required=True, type=Path)
    eff.add_argument("--shell", action="store_true")
    eff.add_argument("args", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    if args.command == "merge":
        changes: dict[str, str] = {}
        for item in args.assignments:
            if "=" not in item:
                parser.error(f"expected KEY=VALUE, got {item!r}")
            key, value = item.split("=", 1)
            changes[key] = value
        saved = merge_config(args.config, changes, args.backup_dir)
        print(json.dumps({"config": str(args.config), "backup": str(saved) if saved else None}))
        return 0

    values = effective(args.codex_home, args.args[1:] if args.args[:1] == ["--"] else args.args)
    if args.shell:
        print(shell_assignment("CORALLINE_MODEL", values["model"]))
        print(shell_assignment("CORALLINE_REASONING", values["reasoning"]))
        print(shell_assignment("CORALLINE_PROFILE", values["profile"]))
    else:
        print(json.dumps(values, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, TOMLDecodeError) as exc:
        print(f"coralline-codex: {exc}", file=sys.stderr)
        raise SystemExit(2)

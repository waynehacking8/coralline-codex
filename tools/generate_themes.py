#!/usr/bin/env python3
"""Generate Codex-compatible TextMate themes from Coralline palettes."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path
from xml.sax.saxutils import escape


def plist(name: str, p: dict[str, str]) -> str:
    settings = [
        ("", p["foreground"]),
        ("comment", p["dim"]),
        ("string, markup.underline.link", p["dir"]),
        ("entity.name.type, support.type, variable", p["model"]),
        ("entity.name.function, entity.name.tag", p["git_ok"]),
        ("keyword, keyword.control", p["git_dirty"]),
        ("constant.numeric, constant", p["duration"]),
        ("constant.language, storage.type", p["profile"]),
        ("storage.modifier, keyword.operator", p["node"]),
        ("markup.heading, entity.name.section", p["project"]),
        ("markup.inserted", p["git_ok"]),
    ]
    blocks = []
    for scope, color in settings:
        scope_xml = f"<key>scope</key><string>{escape(scope)}</string>" if scope else ""
        blocks.append(
            "<dict>" + scope_xml + "<key>settings</key><dict>"
            f"<key>foreground</key><string>{escape(color)}</string>"
            "</dict></dict>"
        )
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
        '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
        '<plist version="1.0"><dict>'
        f'<key>name</key><string>Coralline {escape(name)}</string>'
        '<key>settings</key><array>'
        f'<dict><key>settings</key><dict><key>background</key><string>{p["background"]}</string>'
        f'<key>foreground</key><string>{p["foreground"]}</string></dict></dict>'
        + "".join(blocks)
        + "</array></dict></plist>\n"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--palettes", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    with args.palettes.open(encoding="utf-8", newline="") as handle:
        rows = (line for line in handle if not line.startswith("#"))
        reader = csv.DictReader(
            rows,
            delimiter="\t",
            fieldnames=[
                "name", "background", "foreground", "dir", "project", "git_ok",
                "git_dirty", "node", "python", "model", "profile", "duration", "clock", "dim",
            ],
        )
        for palette in reader:
            name = palette["name"]
            (args.output / f"coralline-{name}.tmTheme").write_text(
                plist(name, palette), encoding="utf-8"
            )


if __name__ == "__main__":
    main()

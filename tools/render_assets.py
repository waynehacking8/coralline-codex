#!/usr/bin/env python3
"""Render deterministic README visuals from the shipped Coralline palettes."""

from __future__ import annotations

import argparse
import html
from pathlib import Path
import sys
from typing import Optional


ROOT = Path(__file__).resolve().parents[1]
PALETTES = ROOT / "themes" / "palettes.tsv"
ASSETS = ROOT / "assets"


def esc(value: object) -> str:
    return html.escape(str(value), quote=True)


def load_palettes() -> list[dict[str, str]]:
    keys = (
        "name", "background", "foreground", "directory", "project", "git_ok",
        "git_dirty", "node", "python", "model", "profile", "duration", "clock", "dim",
    )
    palettes: list[dict[str, str]] = []
    for line in PALETTES.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        values = line.split("\t")
        if len(values) != len(keys):
            raise ValueError(f"invalid palette row: {line}")
        palettes.append(dict(zip(keys, values)))
    return palettes


def powerline_segment(
    x: int,
    y: int,
    label: str,
    color: str,
    foreground: str,
    first: bool = False,
    scale: int = 1,
    font_size: Optional[int] = None,
    height: Optional[int] = None,
) -> tuple[str, int]:
    font_size = font_size or 14 * scale
    height = height or 34 * scale
    horizontal_padding = int(font_size * 2.15)
    width = len(label) * int(font_size * 0.64) + horizontal_padding
    tip = height // 2
    baseline = y + int(height * 0.68)
    if first:
        path = f'M {x} {y} H {x + width} L {x + width + tip} {y + tip} L {x + width} {y + height} H {x} Z'
        text_x = x + horizontal_padding // 2
    else:
        path = (
            f'M {x} {y} L {x + tip} {y + tip} L {x} {y + height} '
            f'H {x + width} L {x + width + tip} {y + tip} L {x + width} {y} Z'
        )
        text_x = x + tip + int(font_size * 0.55)
    svg = (
        f'<path d="{path}" fill="{esc(color)}"/>'
        f'<text x="{text_x}" y="{baseline}" fill="{esc(foreground)}" '
        f'font-size="{font_size}" font-weight="700">{esc(label)}</text>'
    )
    return svg, width


def document(width: int, height: int, body: str, title: str) -> str:
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title desc">
<title id="title">{esc(title)}</title>
<desc id="desc">Generated from themes/palettes.tsv by tools/render_assets.py.</desc>
<style>
text {{ font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace; }}
</style>
{body}
</svg>
'''


def render_hero(palettes: list[dict[str, str]]) -> str:
    width, height = 1334, 1000
    body = [
        '<rect x="1" y="1" width="1332" height="998" rx="14" fill="#0d0f17" stroke="#262b3d" stroke-width="2"/>',
        '<circle cx="28" cy="31" r="7" fill="#ff5f56"/><circle cx="52" cy="31" r="7" fill="#ffbd2e"/><circle cx="76" cy="31" r="7" fill="#27c93f"/>',
        '<text x="667" y="39" fill="#969baf" font-size="20" text-anchor="middle">coralline codex — native footer + active agent rows</text>',
        '<line x1="20" y1="62" x2="1314" y2="62" stroke="#262b3d"/>',
    ]
    selected = {
        palette["name"]: palette
        for palette in palettes
        if palette["name"] in {
            "claude-coral", "catppuccin-mocha", "nord",
            "gruvbox-dark", "tokyo-night", "mono",
        }
    }
    for index, theme_name in enumerate((
        "claude-coral", "catppuccin-mocha", "nord",
        "gruvbox-dark", "tokyo-night", "mono",
    )):
        palette = selected[theme_name]
        label_y = 101 + index * 148
        body.append(
            f'<text x="40" y="{label_y}" fill="#636a87" font-size="15" '
            f'font-weight="700">{esc(theme_name.upper())}</text>'
        )
        rows = (
            (
                ("scout [explorer]", "project"),
                ("Explore config sources", "directory"),
                ("gpt-5.4 high", "model"),
                ("context 21% 42.0k", "profile"),
                ("elapsed 2m05s", "duration"),
            ),
            (
                ("7d 79% reset 1d11h", "git_ok"),
                ("tokens 123.4k", "model"),
                ("context 21%", "profile"),
                ("git main+!?", "git_dirty"),
                ("time 16:53", "clock"),
            ),
        )
        for row_index, segments in enumerate(rows):
            x = 40
            y = label_y + 11 + row_index * 52
            for segment_index, (label, key) in enumerate(segments):
                item, item_width = powerline_segment(
                    x,
                    y,
                    label,
                    palette[key],
                    palette["foreground"],
                    first=segment_index == 0,
                    font_size=18,
                    height=42,
                )
                body.append(item)
                x += item_width
    return document(width, height, "\n".join(body), "Six Coralline Codex themes with active agent rows")


def render_themes(palettes: list[dict[str, str]]) -> str:
    width, height = 1200, 568
    body = [
        '<rect width="1200" height="568" rx="28" fill="#101118"/>',
        '<text x="64" y="66" fill="#ffffff" font-size="30" font-weight="800">Nine bundled themes</text>',
        '<text x="64" y="96" fill="#8d96af" font-size="15">Generated from the same palette data used by the renderer.</text>',
    ]
    for index, palette in enumerate(palettes):
        column = index % 3
        row = index // 3
        x = 64 + column * 376
        y = 130 + row * 134
        body.append(f'<rect x="{x}" y="{y}" width="344" height="104" rx="14" fill="{esc(palette["background"])}" stroke="#343745"/>')
        body.append(f'<text x="{x + 18}" y="{y + 29}" fill="#ffffff" font-size="14" font-weight="700">{esc(palette["name"])}</text>')
        px = x + 18
        for segment_index, (label, key) in enumerate((("94%", "git_ok"), ("tok 12.4k", "model"), ("main", "directory"))):
            item, item_width = powerline_segment(
                px,
                y + 48,
                label,
                palette[key],
                palette["foreground"],
                first=segment_index == 0,
            )
            body.append(item)
            px += item_width
    return document(width, height, "\n".join(body), "Coralline Codex theme gallery")


def outputs() -> dict[Path, str]:
    palettes = load_palettes()
    if len(palettes) != 9:
        raise ValueError(f"expected 9 palettes, found {len(palettes)}")
    return {
        ASSETS / "hero.svg": render_hero(palettes),
        ASSETS / "themes.svg": render_themes(palettes),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail when committed assets are stale")
    args = parser.parse_args()
    rendered = outputs()
    if args.check:
        stale = [str(path.relative_to(ROOT)) for path, value in rendered.items() if not path.exists() or path.read_text(encoding="utf-8") != value]
        if stale:
            print("stale generated assets: " + ", ".join(stale), file=sys.stderr)
            return 1
        print(f"verified {len(rendered)} generated assets")
        return 0
    ASSETS.mkdir(parents=True, exist_ok=True)
    for path, value in rendered.items():
        path.write_text(value, encoding="utf-8")
        print(path.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

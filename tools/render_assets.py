#!/usr/bin/env python3
"""Render deterministic README visuals from the shipped Coralline palettes."""

from __future__ import annotations

import argparse
import html
from pathlib import Path
import sys


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


def pill(x: int, y: int, label: str, color: str, foreground: str, scale: int = 1) -> tuple[str, int]:
    width = (len(label) * 9 + 30) * scale
    height = 34 * scale
    radius = height // 2
    font_size = 14 * scale
    baseline = y + int(22 * scale)
    svg = (
        f'<rect x="{x}" y="{y}" width="{width}" height="{height}" rx="{radius}" fill="{esc(color)}"/>'
        f'<text x="{x + 15 * scale}" y="{baseline}" fill="{esc(foreground)}" '
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


def render_hero(palette: dict[str, str]) -> str:
    width, height = 1200, 440
    body = [
        '<rect width="1200" height="440" rx="28" fill="#101118"/>',
        '<circle cx="84" cy="72" r="8" fill="#ff6b6b"/><circle cx="110" cy="72" r="8" fill="#ffd166"/><circle cx="136" cy="72" r="8" fill="#5faf5f"/>',
        '<text x="80" y="138" fill="#ffffff" font-size="42" font-weight="800">Coralline Codex</text>',
        '<text x="80" y="174" fill="#a8a8a8" font-size="17">Usage limits, session tokens, and a polished terminal companion.</text>',
        '<rect x="64" y="214" width="1072" height="138" rx="18" fill="#1e1f2a" stroke="#343745" stroke-width="2"/>',
        '<text x="90" y="250" fill="#777f98" font-size="13">COMPANION</text>',
    ]
    x = 90
    segments = (
        ("7d [####-] 94% reset 6d18h", palette["git_ok"]),
        ("burn 7d 4d12h", palette["profile"]),
        ("tok 123.4k in:120.0k out:3.4k", palette["model"]),
    )
    for label, color in segments:
        item, item_width = pill(x, 268, label, color, palette["foreground"])
        body.append(item)
        x += item_width + 12
    body.extend(
        (
            '<text x="90" y="334" fill="#8d96af" font-size="13">native footer: model · context remaining · limits · used tokens</text>',
            '<rect x="64" y="382" width="1072" height="1" fill="#2b2e3a"/>',
            '<text x="80" y="414" fill="#7aa2f7" font-size="14" font-weight="700">macOS</text>',
            '<text x="170" y="414" fill="#a8a8a8" font-size="14">full</text>',
            '<text x="260" y="414" fill="#7aa2f7" font-size="14" font-weight="700">Windows WSL</text>',
            '<text x="400" y="414" fill="#a8a8a8" font-size="14">full</text>',
            '<text x="490" y="414" fill="#7aa2f7" font-size="14" font-weight="700">Windows PowerShell</text>',
            '<text x="690" y="414" fill="#a8a8a8" font-size="14">native footer + usage</text>',
            '<text x="1018" y="414" fill="#5faf5f" font-size="14" font-weight="700">v0.2</text>',
        )
    )
    return document(width, height, "\n".join(body), "Coralline Codex terminal usage companion")


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
        for label, key in (("94%", "git_ok"), ("Σ12.4k", "model"), ("main", "directory")):
            item, item_width = pill(px, y + 48, label, palette[key], palette["foreground"])
            body.append(item)
            px += item_width + 8
    return document(width, height, "\n".join(body), "Coralline Codex theme gallery")


def outputs() -> dict[Path, str]:
    palettes = load_palettes()
    if len(palettes) != 9:
        raise ValueError(f"expected 9 palettes, found {len(palettes)}")
    return {
        ASSETS / "hero.svg": render_hero(palettes[0]),
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

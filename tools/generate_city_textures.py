#!/usr/bin/env python3
"""Generate city-specific tileable albedo maps (Pillow)."""

from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "city" / "textures"
SIZE = 1024


def _save(img: Image.Image, name: str) -> None:
    path = OUT / name
    img.convert("RGB").save(path, "JPEG", quality=92)
    print(f"Wrote {path}")


def make_road_line() -> None:
    img = Image.new("RGB", (SIZE, SIZE), (28, 28, 30))
    draw = ImageDraw.Draw(img)
    # Vertical dashed yellow center line (tileable along V)
    cx = SIZE // 2
    dash = 96
    gap = 64
    y = 0
    while y < SIZE:
        draw.rectangle([cx - 6, y, cx + 6, min(y + dash, SIZE)], fill=(220, 190, 40))
        y += dash + gap
    _save(img, "road_line.jpg")


def make_crosswalk() -> None:
    img = Image.new("RGB", (SIZE, SIZE), (32, 32, 34))
    draw = ImageDraw.Draw(img)
    bar_w = 72
    gap = 48
    x = 40
    while x < SIZE - 40:
        draw.rectangle([x, 80, x + bar_w, SIZE - 80], fill=(230, 230, 225))
        x += bar_w + gap
    _save(img, "crosswalk.jpg")


def make_curb() -> None:
    img = Image.new("RGB", (SIZE, SIZE), (150, 148, 142))
    pixels = img.load()
    rng = random.Random(7)
    for y in range(SIZE):
        for x in range(SIZE):
            n = rng.randint(-12, 12)
            # Darker edge bands for wear
            edge = min(x, y, SIZE - 1 - x, SIZE - 1 - y)
            shade = 150 + n - max(0, 18 - edge // 4)
            pixels[x, y] = (shade, shade - 2, shade - 6)
    _save(img, "curb.jpg")


def make_glass() -> None:
    img = Image.new("RGB", (SIZE, SIZE), (140, 175, 200))
    draw = ImageDraw.Draw(img)
    pixels = img.load()
    rng = random.Random(11)
    for y in range(SIZE):
        for x in range(SIZE):
            n = rng.randint(-8, 8)
            pixels[x, y] = (140 + n, 175 + n, 200 + n)
    # Faint mullion grid
    step = 128
    for i in range(0, SIZE, step):
        draw.line([(i, 0), (i, SIZE)], fill=(110, 140, 165), width=3)
        draw.line([(0, i), (SIZE, i)], fill=(110, 140, 165), width=3)
    _save(img, "glass.jpg")


def make_water() -> None:
    img = Image.new("RGB", (SIZE, SIZE))
    pixels = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            # Seamless-ish sine ripples
            wx = math.sin(2 * math.pi * x / SIZE * 4) * 10
            wz = math.sin(2 * math.pi * y / SIZE * 3 + wx * 0.05) * 12
            v = 90 + int(wx + wz)
            pixels[x, y] = (30, 90 + v // 4, 120 + v // 3)
    _save(img, "water.jpg")


def make_leaves() -> None:
    img = Image.new("RGB", (SIZE, SIZE), (45, 95, 40))
    pixels = img.load()
    rng = random.Random(19)
    for y in range(SIZE):
        for x in range(SIZE):
            n = rng.randint(-25, 25)
            # Soft blotches
            blotch = int(18 * math.sin(x * 0.04) * math.cos(y * 0.035))
            g = 95 + n + blotch
            r = 45 + n // 2
            b = 35 + n // 3
            pixels[x, y] = (max(20, r), max(40, min(160, g)), max(20, b))
    _save(img, "leaves.jpg")


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    make_road_line()
    make_crosswalk()
    make_curb()
    make_glass()
    make_water()
    make_leaves()
    print("Generated procedural city textures.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

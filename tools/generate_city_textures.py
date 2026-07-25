#!/usr/bin/env python3
"""Generate city-specific tileable albedo + normal maps (Pillow / NumPy).

Street markings stay simple procedural art. Facade materials for towers and wild
buildings are authored here so they carry panel seams, tile courses and brush —
the ambientCG fillers they replaced were too flat once massing got interesting.
"""

from __future__ import annotations

import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "city" / "textures"
SIZE = 1024


def _save_rgb(arr: np.ndarray, name: str) -> None:
    path = OUT / name
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), mode="RGB")
    img.save(path, "JPEG", quality=93)
    print(f"Wrote {path}")


def _save_img(img: Image.Image, name: str) -> None:
    path = OUT / name
    img.convert("RGB").save(path, "JPEG", quality=93)
    print(f"Wrote {path}")


def _wrap_coords(y: np.ndarray, x: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    return y % SIZE, x % SIZE


def _value_noise(seed: int, octaves: int = 4, base: float = 8.0) -> np.ndarray:
    """Seamless multi-octave value noise in [0, 1]."""
    rng = np.random.default_rng(seed)
    acc = np.zeros((SIZE, SIZE), dtype=np.float64)
    amp = 1.0
    total = 0.0
    freq = base
    for _ in range(octaves):
        gw = max(2, int(round(freq)))
        gh = max(2, int(round(freq)))
        grid = rng.random((gh, gw))
        # Repeat first row/col so bilinear wrap is seamless.
        grid = np.pad(grid, ((0, 1), (0, 1)), mode="wrap")
        ys = np.linspace(0, gh, SIZE, endpoint=False)
        xs = np.linspace(0, gw, SIZE, endpoint=False)
        y0 = np.floor(ys).astype(np.int32)
        x0 = np.floor(xs).astype(np.int32)
        fy = ys - y0
        fx = xs - x0
        y0 = y0 % gh
        x0 = x0 % gw
        y1 = (y0 + 1) % (gh + 1)
        x1 = (x0 + 1) % (gw + 1)
        # Index into padded grid (gh+1, gw+1)
        g00 = grid[y0][:, x0]
        g10 = grid[y1][:, x0]
        g01 = grid[y0][:, x1]
        g11 = grid[y1][:, x1]
        fy2 = fy[:, None]
        fx2 = fx[None, :]
        layer = (
            g00 * (1 - fy2) * (1 - fx2)
            + g10 * fy2 * (1 - fx2)
            + g01 * (1 - fy2) * fx2
            + g11 * fy2 * fx2
        )
        acc += layer * amp
        total += amp
        amp *= 0.5
        freq *= 2.0
    return acc / total


def _height_to_normal(height: np.ndarray, strength: float = 8.0) -> np.ndarray:
    """OpenGL-style normal map from a seamless height field in [0, 1]."""
    h = height.astype(np.float64)
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * strength
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * strength
    nx = -dx
    ny = -dy
    nz = np.ones_like(h)
    inv = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
    r = (nx * inv * 0.5 + 0.5) * 255.0
    g = (ny * inv * 0.5 + 0.5) * 255.0
    b = (nz * inv * 0.5 + 0.5) * 255.0
    return np.stack([r, g, b], axis=-1)


def _save_pair(albedo: np.ndarray, height: np.ndarray, stem: str, n_strength: float) -> None:
    _save_rgb(albedo, f"{stem}.jpg")
    _save_rgb(_height_to_normal(height, n_strength), f"{stem}_normal.jpg")


def make_road_line() -> None:
    img = Image.new("RGB", (SIZE, SIZE), (28, 28, 30))
    draw = ImageDraw.Draw(img)
    cx = SIZE // 2
    dash = 96
    gap = 64
    y = 0
    while y < SIZE:
        draw.rectangle([cx - 6, y, cx + 6, min(y + dash, SIZE)], fill=(220, 190, 40))
        y += dash + gap
    _save_img(img, "road_line.jpg")


def make_crosswalk() -> None:
    img = Image.new("RGB", (SIZE, SIZE), (32, 32, 34))
    draw = ImageDraw.Draw(img)
    bar_w = 72
    gap = 48
    x = 40
    while x < SIZE - 40:
        draw.rectangle([x, 80, x + bar_w, SIZE - 80], fill=(230, 230, 225))
        x += bar_w + gap
    _save_img(img, "crosswalk.jpg")


def make_curb() -> None:
    img = Image.new("RGB", (SIZE, SIZE), (150, 148, 142))
    pixels = img.load()
    rng = random.Random(7)
    for y in range(SIZE):
        for x in range(SIZE):
            n = rng.randint(-12, 12)
            edge = min(x, y, SIZE - 1 - x, SIZE - 1 - y)
            shade = 150 + n - max(0, 18 - edge // 4)
            pixels[x, y] = (shade, shade - 2, shade - 6)
    _save_img(img, "curb.jpg")


def make_glass() -> None:
    img = Image.new("RGB", (SIZE, SIZE), (140, 175, 200))
    draw = ImageDraw.Draw(img)
    pixels = img.load()
    rng = random.Random(11)
    for y in range(SIZE):
        for x in range(SIZE):
            n = rng.randint(-8, 8)
            pixels[x, y] = (140 + n, 175 + n, 200 + n)
    step = 128
    for i in range(0, SIZE, step):
        draw.line([(i, 0), (i, SIZE)], fill=(110, 140, 165), width=3)
        draw.line([(0, i), (i, SIZE)], fill=(110, 140, 165), width=3)
    _save_img(img, "glass.jpg")


def make_water() -> None:
    img = Image.new("RGB", (SIZE, SIZE))
    pixels = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            wx = math.sin(2 * math.pi * x / SIZE * 4) * 10
            wz = math.sin(2 * math.pi * y / SIZE * 3 + wx * 0.05) * 12
            v = 90 + int(wx + wz)
            pixels[x, y] = (30, 90 + v // 4, 120 + v // 3)
    _save_img(img, "water.jpg")


def make_leaves() -> None:
    img = Image.new("RGB", (SIZE, SIZE), (45, 95, 40))
    pixels = img.load()
    rng = random.Random(19)
    for y in range(SIZE):
        for x in range(SIZE):
            n = rng.randint(-25, 25)
            blotch = int(18 * math.sin(x * 0.04) * math.cos(y * 0.035))
            g = 95 + n + blotch
            r = 45 + n // 2
            b = 35 + n // 3
            pixels[x, y] = (max(20, r), max(40, min(160, g)), max(20, b))
    _save_img(img, "leaves.jpg")


def make_metal() -> None:
    """Anodized curtain-wall panels: cool teal-grey, vertical brush, fine seams."""
    n = _value_noise(41, octaves=5, base=6.0)
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    # Vertical brushed grain — phase wraps so the tile seams.
    brush = 0.5 + 0.5 * np.sin((xx + n * 18.0) * (2.0 * math.pi / 7.0))
    panel_u = (xx % 128).astype(np.float64)
    panel_v = (yy % 192).astype(np.float64)
    seam = (
        np.clip(1.0 - np.minimum(panel_u, 128.0 - panel_u) / 3.5, 0.0, 1.0)
        + np.clip(1.0 - np.minimum(panel_v, 192.0 - panel_v) / 3.5, 0.0, 1.0)
    )
    seam = np.clip(seam, 0.0, 1.0)
    base = np.array([118.0, 132.0, 142.0])
    teal = np.array([96.0, 148.0, 156.0])
    mix = 0.35 + 0.45 * n
    rgb = base * (1.0 - mix[..., None]) + teal * mix[..., None]
    rgb += (brush[..., None] - 0.5) * 22.0
    rgb -= seam[..., None] * 38.0
    # Speckle of brighter flakes.
    flake = (_value_noise(77, octaves=2, base=40.0) > 0.82).astype(np.float64)
    rgb += flake[..., None] * 18.0
    height = 0.55 + 0.2 * brush - 0.45 * seam + 0.08 * n
    _save_pair(rgb, height, "metal", 10.0)


def make_metal_plate() -> None:
    """Heavy riveted plates — warm gunmetal for bands and industrial wild forms."""
    n = _value_noise(53, octaves=4, base=5.0)
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    cell = 96
    lu = xx % cell
    lv = yy % cell
    inset = 8
    plate = (
        (lu >= inset)
        & (lu < cell - inset)
        & (lv >= inset)
        & (lv < cell - inset)
    ).astype(np.float64)
    edge = 1.0 - plate
    # Four rivets near the corners of each raised plate.
    rivet_f = np.zeros((SIZE, SIZE), dtype=np.float64)
    for ox, oy in ((inset + 6, inset + 6), (cell - inset - 7, inset + 6),
                   (inset + 6, cell - inset - 7), (cell - inset - 7, cell - inset - 7)):
        d = np.sqrt((lu.astype(np.float64) - ox) ** 2 + (lv.astype(np.float64) - oy) ** 2)
        rivet_f = np.maximum(rivet_f, np.clip(1.0 - d / 5.0, 0.0, 1.0) * plate)
    base = np.array([92.0, 86.0, 78.0])
    rgb = base + (n[..., None] - 0.5) * 28.0
    rgb -= edge[..., None] * 32.0
    rgb += plate[..., None] * 10.0
    rgb = rgb * (1.0 - rivet_f[..., None] * 0.15) + np.array([140.0, 130.0, 110.0]) * rivet_f[
        ..., None
    ]
    height = 0.35 + 0.35 * plate - 0.25 * edge + 0.45 * rivet_f + 0.06 * n
    _save_pair(rgb, height, "metal_plate", 14.0)


def make_paint() -> None:
    """Soft painted plaster with orange-peel and a whisper of hairline crackle."""
    n = _value_noise(19, octaves=5, base=7.0)
    fine = _value_noise(91, octaves=3, base=48.0)
    crack = _value_noise(23, octaves=3, base=18.0)
    # Thin iso-lines only — a wide band reads as camo on large walls.
    crackle = np.clip(1.0 - np.abs(crack - 0.5) * 90.0, 0.0, 1.0)
    crackle *= (_value_noise(31, octaves=2, base=9.0) > 0.55).astype(np.float64)
    base = np.array([214.0, 208.0, 196.0])
    rgb = base + (n[..., None] - 0.5) * 22.0 + (fine[..., None] - 0.5) * 10.0
    rgb -= crackle[..., None] * 18.0
    height = 0.5 + 0.14 * fine - 0.18 * crackle + 0.05 * n
    _save_pair(rgb, height, "paint", 5.0)


def make_tiles() -> None:
    """Glazed diamond tiles — eccentric ceramic for plazas and wild facades."""
    n = _value_noise(61, octaves=4, base=6.0)
    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float64)
    # Diamond lattice in UV.
    u = (xx + yy) / 64.0
    v = (xx - yy) / 64.0
    fu = np.abs(u - np.floor(u) - 0.5)
    fv = np.abs(v - np.floor(v) - 0.5)
    grout = np.clip(1.0 - np.minimum(fu, fv) * 18.0, 0.0, 1.0)
    # Per-tile tint from lattice cell id.
    cell_x = np.floor((xx + yy) / 64.0)
    cell_y = np.floor((xx - yy) / 64.0)
    cell_n = np.sin(cell_x * 12.9898 + cell_y * 78.233) * 43758.5453
    cell_n = cell_n - np.floor(cell_n)
    glaze_a = np.array([72.0, 118.0, 132.0])
    glaze_b = np.array([168.0, 132.0, 96.0])
    glaze_c = np.array([98.0, 92.0, 118.0])
    t = cell_n
    w_a = np.clip(1.0 - t * 2.2, 0.0, 1.0)
    w_b = np.clip(1.0 - np.abs(t - 0.55) * 3.0, 0.0, 1.0)
    w_c = np.clip((t - 0.55) * 2.2, 0.0, 1.0)
    w_sum = np.maximum(w_a + w_b + w_c, 1e-5)
    rgb = (
        glaze_a * (w_a / w_sum)[..., None]
        + glaze_b * (w_b / w_sum)[..., None]
        + glaze_c * (w_c / w_sum)[..., None]
    )
    rgb += (n[..., None] - 0.5) * 16.0
    rgb = rgb * (1.0 - grout[..., None] * 0.55) + np.array([48.0, 46.0, 44.0]) * grout[
        ..., None
    ]
    # Specular glaze flecks.
    fleck = (_value_noise(99, octaves=2, base=64.0) > 0.88).astype(np.float64) * (1.0 - grout)
    rgb += fleck[..., None] * 30.0
    height = 0.62 - 0.5 * grout + 0.08 * n + 0.05 * fleck
    _save_pair(rgb, height, "tiles", 9.0)


def make_roof() -> None:
    """Standing-seam metal roof — dark graphite with clear ridge lines."""
    n = _value_noise(37, octaves=4, base=5.0)
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    seam_pitch = 48
    sx = xx % seam_pitch
    ridge = np.clip(1.0 - np.minimum(sx, seam_pitch - sx).astype(np.float64) / 3.0, 0.0, 1.0)
    # Subtle horizontal weathering bands.
    band = 0.5 + 0.5 * np.sin(yy.astype(np.float64) * (2.0 * math.pi / 96.0) + n * 2.0)
    base = np.array([58.0, 62.0, 68.0])
    rgb = base + (n[..., None] - 0.5) * 18.0
    rgb += ridge[..., None] * 28.0
    rgb -= (1.0 - band)[..., None] * 10.0
    rust = (_value_noise(88, octaves=3, base=10.0) > 0.78).astype(np.float64) * 0.35
    rgb = rgb * (1.0 - rust[..., None]) + np.array([110.0, 72.0, 48.0]) * rust[..., None]
    height = 0.4 + 0.55 * ridge + 0.08 * n
    _save_pair(rgb, height, "roof", 12.0)


def make_roof_clay() -> None:
    """Terracotta pantiles — warm courses that read at pitched-roof distance."""
    n = _value_noise(29, octaves=4, base=6.0)
    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float64)
    course_h = 40.0
    tile_w = 56.0
    # Stagger every other course.
    course = np.floor(yy / course_h)
    stagger = (course % 2) * (tile_w * 0.5)
    lx = (xx + stagger) % tile_w
    ly = yy % course_h
    # Barrel profile per tile.
    barrel = np.sin((lx / tile_w) * math.pi)
    joint_x = np.clip(1.0 - np.minimum(lx, tile_w - lx) / 2.5, 0.0, 1.0)
    joint_y = np.clip(1.0 - np.minimum(ly, course_h - ly) / 2.0, 0.0, 1.0)
    joint = np.clip(joint_x + joint_y, 0.0, 1.0)
    base = np.array([168.0, 78.0, 52.0])
    deep = np.array([120.0, 52.0, 36.0])
    rgb = base * barrel[..., None] + deep * (1.0 - barrel)[..., None]
    rgb += (n[..., None] - 0.5) * 22.0
    rgb -= joint[..., None] * 45.0
    # Occasional darker / lighter tiles.
    cell = np.sin(course * 17.13 + np.floor((xx + stagger) / tile_w) * 9.71)
    cell = cell - np.floor(cell)
    rgb *= 0.88 + 0.24 * cell[..., None]
    height = 0.25 + 0.55 * barrel - 0.4 * joint + 0.06 * n
    _save_pair(rgb, height, "roof_clay", 11.0)


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    make_road_line()
    make_crosswalk()
    make_curb()
    make_glass()
    make_water()
    make_leaves()
    make_metal()
    make_metal_plate()
    make_paint()
    make_tiles()
    make_roof()
    make_roof_clay()
    print("Generated procedural city textures.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Download ambientCG 1K-JPG Color + Normal maps into assets/city/textures/."""

from __future__ import annotations

import io
import sys
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "city" / "textures"

# ambientCG asset id -> destination filename (Color / albedo).
# Tower / wild facade maps (metal, plates, paint, tiles, roofs) are project-authored
# in generate_city_textures.py — keep them out of this list so a refresh cannot
# quietly flatten them back to ambientCG fillers.
MANIFEST: dict[str, str] = {
    "Plaster001": "plaster.jpg",
    "Bricks097": "brick_dark.jpg",
    "Gravel023": "gravel.jpg",
    "Ground054": "dirt.jpg",
    "Bark014": "bark.jpg",
    "PavingStones128": "stone.jpg",
}

# Normals, one per albedo. Every ambientCG zip the colour maps come from already ships a
# NormalGL map, so a surface that renders as printed lino is a map we downloaded and threw
# away — including the largest ground planes in the game (lawn, plaza, gravel, dirt).
NORMAL_MANIFEST: dict[str, str] = {
    "Asphalt031": "asphalt_normal.jpg",
    "Bark014": "bark_normal.jpg",
    "Bricks075A": "brick_normal.jpg",
    # Bricks097 is real coursed brick; brick_dark.jpg used to borrow the rough rubble
    # relief of Bricks075A, so the bump never followed its own courses.
    "Bricks097": "brick_dark_normal.jpg",
    "Concrete034": "concrete_normal.jpg",
    "Grass001": "grass_normal.jpg",
    "Gravel023": "gravel_normal.jpg",
    "Ground054": "dirt_normal.jpg",
    "PavingStones037": "sidewalk_normal.jpg",
    "PavingStones070": "plaza_normal.jpg",
    "PavingStones128": "stone_normal.jpg",
    "Plaster001": "plaster_normal.jpg",
    "Rock050": "rock_normal.jpg",
    "Wood051": "wood_normal.jpg",
}


def _open_zip(asset_id: str) -> zipfile.ZipFile:
    url = f"https://ambientcg.com/get?file={asset_id}_1K-JPG.zip"
    print(f"GET {url}")
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "CityTextureFetch/1.0 (+local procedural city; CC0 assets)",
            "Accept": "*/*",
        },
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = resp.read()
    return zipfile.ZipFile(io.BytesIO(data))


def _pick_member(names: list[str], *needles: str) -> str | None:
    lowered = [(n, n.lower()) for n in names]
    for needle in needles:
        for name, low in lowered:
            if needle in low and low.endswith((".jpg", ".jpeg")):
                return name
    return None


def download_color(asset_id: str, dest: Path) -> None:
    with _open_zip(asset_id) as zf:
        color_name = _pick_member(zf.namelist(), "color.jpg", "color.jpeg")
        if color_name is None:
            color_name = _pick_member(zf.namelist(), "color")
        if color_name is None:
            raise RuntimeError(f"No Color.jpg in {asset_id} zip: {zf.namelist()}")
        dest.write_bytes(zf.read(color_name))
        print(f"  -> {dest.name} ({dest.stat().st_size} bytes) from {color_name}")


def download_normal(asset_id: str, dest: Path) -> None:
    with _open_zip(asset_id) as zf:
        # Prefer OpenGL-style normals (NormalGL) used by Godot.
        normal_name = _pick_member(
            zf.namelist(),
            "normalgl.jpg",
            "normalgl.jpeg",
            "normal.jpg",
            "normal.jpeg",
            "normaldx.jpg",
        )
        if normal_name is None:
            normal_name = _pick_member(zf.namelist(), "normal")
        if normal_name is None:
            raise RuntimeError(f"No Normal map in {asset_id} zip: {zf.namelist()}")
        dest.write_bytes(zf.read(normal_name))
        print(f"  -> {dest.name} ({dest.stat().st_size} bytes) from {normal_name}")


# Colour maps fetched before this script kept a MANIFEST. They are still ambientCG CC0
# and still shipped, so they have to stay credited even though nothing re-downloads them.
LEGACY_COLOR: dict[str, str] = {
    "asphalt.jpg": "Asphalt031",
    "brick.jpg": "Bricks075A",
    "concrete.jpg": "Concrete034",
    "sidewalk.jpg": "PavingStones037",
    "plaza.jpg": "PavingStones070",
    "grass.jpg": "Grass001",
    "wood.jpg": "Wood051",
    "rock.jpg": "Rock050",
}

# Everything generate_city_textures.py authors, in the order it writes them.
AUTHORED: list[str] = [
    "road_line.jpg, crosswalk.jpg — street markings",
    "glass.jpg — curtain-wall glazing with mullions",
    "water.jpg — pond / lake ripple sheet",
    "leaves.png — deciduous canopy cards (alpha cutout)",
    "metal.jpg / metal_normal.jpg — anodized curtain-wall panels",
    "metal_plate.jpg / metal_plate_normal.jpg — riveted industrial plates",
    "paint.jpg / paint_normal.jpg — painted plaster with crackle",
    "tiles.jpg / tiles_normal.jpg — glazed diamond ceramic",
    "roof.jpg / roof_normal.jpg — standing-seam metal roof",
    "roof_clay.jpg / roof_clay_normal.jpg — terracotta pantiles",
    "cave_wall.jpg / cave_wall_normal.jpg — damp limestone for hill caves",
    "cave_floor.jpg / cave_floor_normal.jpg — packed damp earth cave floors",
    "grave_stone.jpg / grave_stone_normal.jpg — lichen-blackened granite",
    "grave_marble.jpg / grave_marble_normal.jpg — monument marble",
    "grave_soil.jpg / grave_soil_normal.jpg — turned grave plots",
    "grave_path.jpg / grave_path_normal.jpg — cinder aisles",
    "wrought_iron.jpg / wrought_iron_normal.jpg — railings and finials",
    "yew.png — churchyard yew cards (alpha cutout)",
]


def write_credits() -> None:
    credits = OUT / "CREDITS.txt"
    lines = [
        "Textures from ambientCG (https://ambientcg.com/)",
        "License: CC0 1.0 Universal (public domain dedication)",
        "",
        "Asset IDs used (1K-JPG Color/albedo maps):",
    ]
    colors = dict(LEGACY_COLOR)
    for asset_id, fname in MANIFEST.items():
        colors[fname] = asset_id
    for fname in sorted(colors):
        lines.append(f"- {fname} <- {colors[fname]}")
    lines.extend(["", "Normal maps (1K-JPG NormalGL):"])
    for fname in sorted(NORMAL_MANIFEST.values()):
        asset_id = next(a for a, f in NORMAL_MANIFEST.items() if f == fname)
        lines.append(f"- {fname} <- {asset_id}")
    lines.extend(["", "Project-authored (see generate_city_textures.py):"])
    for entry in AUTHORED:
        lines.append(f"- {entry}")
    lines.append("")
    credits.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {credits}")


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    errors: list[str] = []
    for asset_id, fname in MANIFEST.items():
        dest = OUT / fname
        try:
            download_color(asset_id, dest)
        except Exception as exc:  # noqa: BLE001 — report all failures
            errors.append(f"{asset_id} color: {exc}")
            print(f"FAILED {asset_id} color: {exc}", file=sys.stderr)
    for asset_id, fname in NORMAL_MANIFEST.items():
        dest = OUT / fname
        try:
            download_normal(asset_id, dest)
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{asset_id} normal: {exc}")
            print(f"FAILED {asset_id} normal: {exc}", file=sys.stderr)
    write_credits()
    if errors:
        print(f"{len(errors)} download(s) failed", file=sys.stderr)
        return 1
    print("All ambientCG textures fetched.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Download ambientCG 1K-JPG Color maps into assets/city/textures/."""

from __future__ import annotations

import io
import sys
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "city" / "textures"

# ambientCG asset id -> destination filename
MANIFEST: dict[str, str] = {
    "Plaster001": "plaster.jpg",
    "Metal049A": "metal.jpg",
    "Bricks097": "brick_dark.jpg",
    "Gravel023": "gravel.jpg",
    "Ground054": "dirt.jpg",
    "Terrazzo013": "tiles.jpg",
    "RoofingTiles013A": "roof_clay.jpg",
    "MetalPlates006": "metal_plate.jpg",
    "Paint001": "paint.jpg",
    "Bark014": "bark.jpg",
    "PavingStones128": "stone.jpg",
}


def download_color(asset_id: str, dest: Path) -> None:
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
    with zipfile.ZipFile(io.BytesIO(data)) as zf:
        color_name = None
        for name in zf.namelist():
            lower = name.lower()
            if lower.endswith("color.jpg") or lower.endswith("color.jpeg"):
                color_name = name
                break
        if color_name is None:
            # Fallback: any *Color*
            for name in zf.namelist():
                if "color" in name.lower() and name.lower().endswith((".jpg", ".jpeg")):
                    color_name = name
                    break
        if color_name is None:
            raise RuntimeError(f"No Color.jpg in {asset_id} zip: {zf.namelist()}")
        dest.write_bytes(zf.read(color_name))
        print(f"  -> {dest.name} ({dest.stat().st_size} bytes) from {color_name}")


def write_credits(existing_ids: list[str]) -> None:
    credits = OUT / "CREDITS.txt"
    lines = [
        "Textures from ambientCG (https://ambientcg.com/)",
        "License: CC0 1.0 Universal (public domain dedication)",
        "",
        "Asset IDs used (1K-JPG Color/albedo maps):",
        "- asphalt.jpg <- Asphalt031",
        "- brick.jpg <- Bricks075A",
        "- concrete.jpg <- Concrete034",
        "- sidewalk.jpg <- PavingStones037",
        "- plaza.jpg <- PavingStones070",
        "- grass.jpg <- Grass001",
        "- roof.jpg <- RoofingTiles014A",
        "- wood.jpg <- Wood051",
        "- rock.jpg <- Rock050",
    ]
    for asset_id, fname in MANIFEST.items():
        lines.append(f"- {fname} <- {asset_id}")
    lines.extend(
        [
            "",
            "Project-authored (see generate_city_textures.py):",
            "- glass.jpg, water.jpg, leaves.jpg, curb.jpg, road_line.jpg, crosswalk.jpg",
            "",
        ]
    )
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
            errors.append(f"{asset_id}: {exc}")
            print(f"FAILED {asset_id}: {exc}", file=sys.stderr)
    write_credits(list(MANIFEST.keys()))
    if errors:
        print(f"{len(errors)} download(s) failed", file=sys.stderr)
        return 1
    print("All ambientCG textures fetched.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

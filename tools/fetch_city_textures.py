#!/usr/bin/env python3
"""Download ambientCG Color + Normal maps into assets/city/textures/.

Most maps stay on the 1K-JPG pack. Stone / castle rock uses a 2K fine-grained
rock face so curtain walls don't read as soft paving-stone ashlar.
"""

from __future__ import annotations

import io
import sys
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "city" / "textures"

# ambientCG asset id -> (destination filename, pack resolution suffix).
# Tower / wild facade maps (metal, plates, paint, tiles, roofs) are project-authored
# in generate_city_textures.py — keep them out of this list so a refresh cannot
# quietly flatten them back to ambientCG fillers.
MANIFEST: dict[str, tuple[str, str]] = {
	"Plaster001": ("plaster.jpg", "1K"),
	"Bricks097": ("brick_dark.jpg", "1K"),
	"Gravel023": ("gravel.jpg", "1K"),
	"Ground054": ("dirt.jpg", "1K"),
	"Bark014": ("bark.jpg", "1K"),
	## Fine-grained seamless rock face (not paving ashlar) for STONE / CASTLE_BLOCK.
	"Rock020": ("stone.jpg", "2K"),
}

# Normals, one per albedo. Every ambientCG zip the colour maps come from already ships a
# NormalGL map, so a surface that renders as printed lino is a map we downloaded and threw
# away — including the largest ground planes in the game (lawn, plaza, gravel, dirt).
NORMAL_MANIFEST: dict[str, tuple[str, str]] = {
	"Asphalt031": ("asphalt_normal.jpg", "1K"),
	"Bark014": ("bark_normal.jpg", "1K"),
	"Bricks075A": ("brick_normal.jpg", "1K"),
	# Bricks097 is real coursed brick; brick_dark.jpg used to borrow the rough rubble
	# relief of Bricks075A, so the bump never followed its own courses.
	"Bricks097": ("brick_dark_normal.jpg", "1K"),
	"Concrete034": ("concrete_normal.jpg", "1K"),
	"Grass001": ("grass_normal.jpg", "1K"),
	"Gravel023": ("gravel_normal.jpg", "1K"),
	"Ground054": ("dirt_normal.jpg", "1K"),
	"PavingStones037": ("sidewalk_normal.jpg", "1K"),
	"PavingStones070": ("plaza_normal.jpg", "1K"),
	"Rock020": ("stone_normal.jpg", "2K"),
	"Plaster001": ("plaster_normal.jpg", "1K"),
	"Rock050": ("rock_normal.jpg", "1K"),
	"Wood051": ("wood_normal.jpg", "1K"),
}


def _open_zip(asset_id: str, res: str) -> zipfile.ZipFile:
	url = f"https://ambientcg.com/get?file={asset_id}_{res}-JPG.zip"
	print(f"GET {url}")
	req = urllib.request.Request(
		url,
		headers={
			"User-Agent": "CityTextureFetch/1.0 (+local procedural city; CC0 assets)",
			"Accept": "*/*",
		},
	)
	with urllib.request.urlopen(req, timeout=180) as resp:
		data = resp.read()
	return zipfile.ZipFile(io.BytesIO(data))


def _pick_member(names: list[str], *needles: str) -> str | None:
	lowered = [(n, n.lower()) for n in names]
	for needle in needles:
		for name, low in lowered:
			if needle in low and low.endswith((".jpg", ".jpeg")):
				return name
	return None


def download_color(asset_id: str, dest: Path, res: str) -> None:
	with _open_zip(asset_id, res) as zf:
		color_name = _pick_member(zf.namelist(), "color.jpg", "color.jpeg")
		if color_name is None:
			color_name = _pick_member(zf.namelist(), "color")
		if color_name is None:
			raise RuntimeError(f"No Color.jpg in {asset_id} zip: {zf.namelist()}")
		dest.write_bytes(zf.read(color_name))
		print(f"  -> {dest.name} ({dest.stat().st_size} bytes) from {color_name} [{res}]")


def download_normal(asset_id: str, dest: Path, res: str) -> None:
	with _open_zip(asset_id, res) as zf:
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
		print(f"  -> {dest.name} ({dest.stat().st_size} bytes) from {normal_name} [{res}]")


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
		"Asset IDs used (Color/albedo maps):",
	]
	colors = dict(LEGACY_COLOR)
	res_note: dict[str, str] = {}
	for asset_id, (fname, res) in MANIFEST.items():
		colors[fname] = asset_id
		res_note[fname] = res
	for fname in sorted(colors):
		asset = colors[fname]
		pack = res_note.get(fname, "1K")
		lines.append(f"- {fname} <- {asset} ({pack}-JPG)")
	lines.extend(["", "Normal maps (NormalGL):"])
	for asset_id, (fname, res) in sorted(NORMAL_MANIFEST.items(), key=lambda kv: kv[1][0]):
		lines.append(f"- {fname} <- {asset_id} ({res}-JPG)")
	lines.extend(["", "Project-authored (see generate_city_textures.py):"])
	for entry in AUTHORED:
		lines.append(f"- {entry}")
	lines.append("")
	credits.write_text("\n".join(lines), encoding="utf-8")
	print(f"Wrote {credits}")


def main() -> int:
	OUT.mkdir(parents=True, exist_ok=True)
	errors: list[str] = []
	for asset_id, (fname, res) in MANIFEST.items():
		dest = OUT / fname
		try:
			download_color(asset_id, dest, res)
		except Exception as exc:  # noqa: BLE001 — report all failures
			errors.append(f"{asset_id} color: {exc}")
			print(f"FAILED {asset_id} color: {exc}", file=sys.stderr)
	for asset_id, (fname, res) in NORMAL_MANIFEST.items():
		dest = OUT / fname
		try:
			download_normal(asset_id, dest, res)
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

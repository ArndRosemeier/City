#!/usr/bin/env python3
"""Build the full room-prop kit from Kenney Furniture (CC0) + authored barrel.

Writes:
  assets/city/props/<stem>.obj     — meshes in voxel units (may span many cells)
  assets/city/props/CREDITS.txt
  scripts/city/room_prop_catalog.gd — ID table, families, sizes, collision AABBs
  patches COUNT in voxel_material.gd + materials.rs (PROP_FIRST..PROP_FOOTPRINT)

Skips Kenney architectural fillers (walls/floors/doorways) — those are city voxels.

Scale: Kenney chair height → 1.0 m, voxels are 0.5 m. A single bed lands ~3×2×5 cells.
"""

from __future__ import annotations

import math
import re
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC_ZIP = ROOT / "tools" / "_prop_src" / "kenney_furniturePack.zip"
SRC_DIR = ROOT / "tools" / "_prop_src" / "kenney_furniture"
OUT_PROPS = ROOT / "assets" / "city" / "props"
CATALOG_GD = ROOT / "scripts" / "city" / "room_prop_catalog.gd"
VOXEL_MAT_GD = ROOT / "scripts" / "city" / "voxel_material.gd"
MATERIALS_RS = ROOT / "native" / "city_voxel" / "src" / "materials.rs"
KENNEY_URL = "https://opengameart.org/sites/default/files/kenney_furniturePack.zip"

PROP_FIRST = 75
VOXEL_M = 0.5
## Map Kenney's chair overall height to this many metres (≈ two voxels).
CHAIR_HEIGHT_M = 1.0
## Cap so a dining table cannot claim half a keep room.
MAX_AXIS_VOX = 6
MARGIN_VOX = 0.04

# Kenney stems to skip — building fabric, not furniture.
SKIP_PREFIXES = (
	"wall",
	"floor",
	"doorway",
	"paneling",
)

# Explicit skips (stem).
SKIP_EXACT = {
	"doorwayFront",
	"doorwayOpen",
}

# Authored extras not in Kenney (stem, family).
AUTHORED: list[tuple[str, str]] = [
	("barrel", "wood"),
]


def family_for(stem: str) -> str:
	s = stem.lower()
	if any(k in s for k in ("plant", "potted")):
		return "foliage"
	if any(k in s for k in ("rug", "pillow", "cushion", "sofa", "ottoman", "bed")):
		return "fabric"
	if any(
		k in s
		for k in (
			"fridge",
			"stove",
			"washer",
			"dryer",
			"microwave",
			"blender",
			"coffee",
			"television",
			"computer",
			"laptop",
			"speaker",
			"radio",
			"lamp",
			"fan",
			"trash",
		)
	):
		return "metal"
	if any(k in s for k in ("toilet", "bathtub", "shower", "sink", "mirror")):
		return "ceramic"
	return "wood"


def walk_through(stem: str, family: str) -> bool:
	s = stem.lower()
	if family == "foliage":
		return True
	if any(k in s for k in ("lamp", "plant", "pillow", "rug", "books", "bear")):
		return True
	return False


def ensure_kenney() -> Path:
	models = SRC_DIR / "Models"
	if models.is_dir() and any(models.glob("*.obj")):
		return models
	SRC_DIR.mkdir(parents=True, exist_ok=True)
	SRC_ZIP.parent.mkdir(parents=True, exist_ok=True)
	if not SRC_ZIP.is_file():
		print(f"GET {KENNEY_URL}")
		req = urllib.request.Request(KENNEY_URL, headers={"User-Agent": "CityProps/1.0"})
		with urllib.request.urlopen(req, timeout=180) as resp:
			SRC_ZIP.write_bytes(resp.read())
	with zipfile.ZipFile(SRC_ZIP) as zf:
		zf.extractall(SRC_DIR)
	return models


def load_obj(path: Path) -> tuple[list[list[float]], list[list[int]]]:
	verts: list[list[float]] = []
	faces: list[list[int]] = []
	for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
		if line.startswith("v "):
			p = line.split()
			verts.append([float(p[1]), float(p[2]), float(p[3])])
		elif line.startswith("f "):
			idx = [int(t.split("/")[0]) - 1 for t in line.split()[1:]]
			for i in range(1, len(idx) - 1):
				faces.append([idx[0], idx[i], idx[i + 1]])
	if not verts or not faces:
		raise RuntimeError(f"empty OBJ {path}")
	return verts, faces


def bounds(verts: list[list[float]]) -> tuple[list[float], list[float], list[float]]:
	lo = [min(v[i] for v in verts) for i in range(3)]
	hi = [max(v[i] for v in verts) for i in range(3)]
	size = [max(hi[i] - lo[i], 1e-6) for i in range(3)]
	return lo, hi, size


def chair_meters_per_unit(models: Path) -> float:
	path = models / "chair.obj"
	verts, _ = load_obj(path)
	_lo, _hi, size = bounds(verts)
	return CHAIR_HEIGHT_M / size[1]


def fit_voxel_footprint(
	verts: list[list[float]], m_per_u: float
) -> tuple[list[list[float]], tuple[int, int, int]]:
	"""Uniform Kenney→voxel scale; integer footprint is the ceil of the scaled AABB."""
	lo, _hi, size_k = bounds(verts)
	scale = m_per_u / VOXEL_M
	size_v = [size_k[i] * scale for i in range(3)]
	nx = max(1, min(MAX_AXIS_VOX, int(math.ceil(size_v[0] - 1e-4))))
	ny = max(1, min(MAX_AXIS_VOX, int(math.ceil(size_v[1] - 1e-4))))
	nz = max(1, min(MAX_AXIS_VOX, int(math.ceil(size_v[2] - 1e-4))))
	## If ceil hit the cap, shrink uniformly so the mesh still fits the box.
	fit = min(
		(nx - 2.0 * MARGIN_VOX) / size_v[0],
		(ny - 2.0 * MARGIN_VOX) / size_v[1],
		(nz - 2.0 * MARGIN_VOX) / size_v[2],
		1.0,
	)
	scale *= fit
	size_v = [size_k[i] * scale for i in range(3)]
	ox = (nx - size_v[0]) * 0.5
	oy = MARGIN_VOX
	oz = (nz - size_v[2]) * 0.5
	out: list[list[float]] = []
	for v in verts:
		out.append(
			[
				(v[0] - lo[0]) * scale + ox,
				(v[1] - lo[1]) * scale + oy,
				(v[2] - lo[2]) * scale + oz,
			]
		)
	return out, (nx, ny, nz)


def aabb_of(
	verts: list[list[float]], size_vox: tuple[int, int, int], pad: float = 0.02
) -> tuple[float, float, float, float, float, float]:
	lo = [min(v[i] for v in verts) for i in range(3)]
	hi = [max(v[i] for v in verts) for i in range(3)]
	nx, ny, nz = size_vox
	ox = max(0.0, lo[0] - pad)
	oy = max(0.0, lo[1])
	oz = max(0.0, lo[2] - pad)
	sx = min(float(nx), hi[0] + pad) - ox
	sy = min(float(ny), hi[1] + pad) - oy
	sz = min(float(nz), hi[2] + pad) - oz
	return (ox, oy, oz, max(sx, 0.05), max(sy, 0.05), max(sz, 0.05))


def write_obj(
	path: Path, verts: list[list[float]], faces: list[list[int]], size_vox: tuple[int, int, int]
) -> None:
	nx, ny, nz = size_vox
	lines = [
		f"# City room prop — voxel footprint {nx}x{ny}x{nz} (0.5 m cells)",
		f"o {path.stem}",
	]
	for v in verts:
		lines.append(f"v {v[0]:.6f} {v[1]:.6f} {v[2]:.6f}")
	for f in faces:
		lines.append(f"f {f[0] + 1} {f[1] + 1} {f[2] + 1}")
	path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def make_barrel(segments: int = 16) -> tuple[list[list[float]], list[list[int]], tuple[int, int, int]]:
	"""~0.7 m drum in a 2×2×2 voxel box."""
	verts: list[list[float]] = []
	faces: list[list[int]] = []
	size = (2, 2, 2)
	cx = cz = 1.0
	y0, y1 = 0.06, 1.85
	r_mid, r_end = 0.72, 0.60

	def ring(y: float, r: float) -> list[int]:
		ids: list[int] = []
		for i in range(segments):
			a = (i / segments) * math.tau
			verts.append([cx + math.cos(a) * r, y, cz + math.sin(a) * r])
			ids.append(len(verts) - 1)
		return ids

	ys = [y0, 0.4, 0.95, 1.5, y1]
	rs = [r_end, r_mid, r_mid + 0.04, r_mid, r_end]
	rings = [ring(y, r) for y, r in zip(ys, rs)]
	for ri in range(len(rings) - 1):
		a, b = rings[ri], rings[ri + 1]
		for i in range(segments):
			j = (i + 1) % segments
			faces.append([a[i], b[i], b[j]])
			faces.append([a[i], b[j], a[j]])
	top_c = len(verts)
	verts.append([cx, y1, cz])
	bot_c = len(verts)
	verts.append([cx, y0, cz])
	for i in range(segments):
		j = (i + 1) % segments
		faces.append([top_c, rings[-1][j], rings[-1][i]])
		faces.append([bot_c, rings[0][i], rings[0][j]])
	return verts, faces, size

def select_stems(models: Path) -> list[str]:
	stems: list[str] = []
	for p in sorted(models.glob("*.obj")):
		stem = p.stem
		# Normalize "kitchenCabinetDrawer 1" → kitchenCabinetDrawer1
		safe = re.sub(r"[^A-Za-z0-9_]+", "", stem.replace(" ", ""))
		low = safe.lower()
		if safe in SKIP_EXACT or stem in SKIP_EXACT:
			continue
		if any(low.startswith(pref) for pref in SKIP_PREFIXES):
			continue
		stems.append(stem)
	return stems


def safe_stem(stem: str) -> str:
	return re.sub(r"[^A-Za-z0-9_]+", "", stem.replace(" ", ""))


def write_catalog_gd(entries: list[dict]) -> None:
	lines = [
		"## AUTO-GENERATED by tools/gen_room_prop_catalog.py — do not edit by hand.",
		"## Room prop ID table: VoxelMaterial.PROP_FIRST + index.",
		"class_name RoomPropCatalog",
		"extends RefCounted",
		"",
		"const PROP_MESH_DIR := \"res://assets/city/props/\"",
		f"const PROP_FIRST := {PROP_FIRST}",
		f"const PROP_COUNT := {len(entries)}",
		f"const PROP_LAST := {PROP_FIRST + len(entries) - 1}",
		"",
		"## stem, family, walk_through, size (voxel cells), aabb(x,y,z,sx,sy,sz) in voxel units",
		"const ENTRIES: Array[Dictionary] = [",
	]
	for e in entries:
		aabb = e["aabb"]
		sx, sy, sz = e["size"]
		lines.append(
			"\t{"
			f"\"stem\": \"{e['stem']}\", "
			f"\"family\": \"{e['family']}\", "
			f"\"walk_through\": {str(e['walk_through']).lower()}, "
			f"\"size\": Vector3i({sx}, {sy}, {sz}), "
			f"\"aabb\": Vector3({aabb[0]:.4f}, {aabb[1]:.4f}, {aabb[2]:.4f}), "
			f"\"aabb_size\": Vector3({aabb[3]:.4f}, {aabb[4]:.4f}, {aabb[5]:.4f})"
			"},"
		)
	lines.append("]")
	lines.append("")
	lines.append(
		"""
static func is_prop_id(id: int) -> bool:
	return id >= PROP_FIRST and id <= PROP_LAST


static func index_of(id: int) -> int:
	return id - PROP_FIRST


static func entry(id: int) -> Dictionary:
	var i := index_of(id)
	if i < 0 or i >= ENTRIES.size():
		push_error("RoomPropCatalog.entry: bad id %d" % id)
		return {}
	return ENTRIES[i]


static func stem_of(id: int) -> String:
	var e := entry(id)
	return String(e.get("stem", ""))


static func family_of(id: int) -> String:
	var e := entry(id)
	return String(e.get("family", "wood"))


static func size_of_id(id: int) -> Vector3i:
	var e := entry(id)
	return e.get("size", Vector3i.ONE) as Vector3i


static func size_of_stem(stem: String) -> Vector3i:
	var id := find_stem(stem)
	if id < PROP_FIRST:
		return Vector3i.ONE
	return size_of_id(id)


static func mesh_path(id: int) -> String:
	return PROP_MESH_DIR + stem_of(id) + ".obj"


static func kit_names() -> PackedStringArray:
	var out := PackedStringArray()
	for e in ENTRIES:
		out.append(String(e["stem"]))
	return out


static func find_stem(stem: String) -> int:
	for i in range(ENTRIES.size()):
		if String(ENTRIES[i]["stem"]) == stem:
			return PROP_FIRST + i
	return 0


static func id_for_stem(stem: String) -> int:
	var id := find_stem(stem)
	if id < PROP_FIRST:
		push_error("RoomPropCatalog.id_for_stem: unknown %s" % stem)
		return 0
	return id
""".strip()
	)
	CATALOG_GD.write_text("\n".join(lines) + "\n", encoding="utf-8")
	print(f"Wrote {CATALOG_GD} ({len(entries)} props)")


def patch_voxel_material(count: int, last: int) -> None:
	text = VOXEL_MAT_GD.read_text(encoding="utf-8")
	# Replace old PROP_* block + COUNT with range constants.
	pattern = re.compile(
		r"## Room prop kit.*?const COUNT := \d+",
		re.DOTALL,
	)
	footprint = last + 1
	total = footprint + 1
	replacement = (
		"## Room prop kit — see RoomPropCatalog / tools/gen_room_prop_catalog.py.\n"
		f"const PROP_FIRST := {PROP_FIRST}\n"
		f"const PROP_LAST := {last}\n"
		f"const PROP_COUNT := {count}\n"
		"## Invisible solid filler for multi-cell prop footprints (nav / occupancy).\n"
		f"const PROP_FOOTPRINT := {footprint}\n"
		"## Legacy aliases (first kit) — prefer RoomPropCatalog.id_for_stem.\n"
		"const PROP_CRATE := PROP_FIRST\n"
		"const PROP_BARREL := PROP_FIRST + 1\n"
		"const PROP_CHAIR := PROP_FIRST + 2\n"
		f"const COUNT := {total}"
	)
	if pattern.search(text):
		text = pattern.sub(replacement, text)
	else:
		# Insert before COUNT if props block missing.
		text = re.sub(
			r"const COUNT := \d+",
			replacement,
			text,
			count=1,
		)
	# Fix is_room_prop
	text = re.sub(
		r"static func is_room_prop\(id: int\) -> bool:\n\treturn id >= PROP_CRATE and id <= PROP_CHEST",
		"static func is_room_prop(id: int) -> bool:\n\treturn id >= PROP_FIRST and id <= PROP_LAST",
		text,
	)
	# Ensure is_room_prop / is_prop_furniture helpers exist.
	if "static func is_prop_furniture" not in text:
		text = text.replace(
			"static func is_room_prop(id: int) -> bool:\n\treturn id >= PROP_FIRST and id <= PROP_LAST\n",
			(
				"static func is_room_prop(id: int) -> bool:\n"
				"\treturn id >= PROP_FIRST and id <= PROP_LAST\n"
				"\n"
				"\n"
				"## Visible prop mesh or its invisible multi-cell footprint filler.\n"
				"static func is_prop_furniture(id: int) -> bool:\n"
				"\treturn is_room_prop(id) or id == PROP_FOOTPRINT\n"
			),
		)
	VOXEL_MAT_GD.write_text(text, encoding="utf-8")
	print(f"Patched {VOXEL_MAT_GD} COUNT={footprint + 1} FOOTPRINT={footprint}")


def patch_materials_rs(count: int, last: int) -> None:
	footprint = last + 1
	total = footprint + 1
	text = MATERIALS_RS.read_text(encoding="utf-8")
	text = re.sub(
		r"pub const PROP_FIRST: i32 = \d+;.*?pub const COUNT: i32 = \d+;",
		(
			f"pub const PROP_FIRST: i32 = {PROP_FIRST};\n"
			f"#[allow(dead_code)]\n"
			f"pub const PROP_LAST: i32 = {last};\n"
			f"#[allow(dead_code)]\n"
			f"pub const PROP_FOOTPRINT: i32 = {footprint};\n"
			f"pub const COUNT: i32 = {total};"
		),
		text,
		flags=re.DOTALL,
	)
	MATERIALS_RS.write_text(text, encoding="utf-8")
	print(f"Patched {MATERIALS_RS} COUNT={total}")


def write_credits(n: int) -> None:
	OUT_PROPS.mkdir(parents=True, exist_ok=True)
	(OUT_PROPS / "CREDITS.txt").write_text(
		f"""Room prop meshes (multi-cell voxel footprints) — {n} pieces

Scale: Kenney chair height → {CHAIR_HEIGHT_M} m; city voxels are {VOXEL_M} m.
A single bed is several cells long — not crushed into one voxel.

Sources
- Kenney Furniture Kit (CC0 1.0) — https://kenney.nl/assets/furniture-kit
  OpenGameArt mirror; scaled by tools/gen_room_prop_catalog.py
- barrel.obj — project-authored lathed cylinder

Regenerate: python tools/gen_room_prop_catalog.py
""",
		encoding="utf-8",
	)


def main() -> int:
	OUT_PROPS.mkdir(parents=True, exist_ok=True)
	# Clear old prop objs (keep import files; Godot refreshes).
	for old in OUT_PROPS.glob("*.obj"):
		old.unlink()

	models = ensure_kenney()
	m_per_u = chair_meters_per_unit(models)
	print(f"Kenney scale: {m_per_u:.4f} m/unit (chair -> {CHAIR_HEIGHT_M} m)")
	kenney_stems = select_stems(models)
	entries: list[dict] = []

	# Authored first so legacy PROP_CRATE/BARREL/CHAIR aliases stay stable if we put
	# crate/barrel/chair at the front intentionally.
	priority = ["cardboardBoxClosed", "barrel", "chair"]
	ordered: list[tuple[str, str | None]] = []
	# (display_stem_for_file, source_stem_or_None)
	seen_safe: set[str] = set()

	def add(file_stem: str, src_stem: str | None) -> None:
		safe = safe_stem(file_stem)
		if safe in seen_safe:
			return
		seen_safe.add(safe)
		ordered.append((safe, src_stem))

	add("crate", "cardboardBoxClosed")  # friendly alias
	add("barrel", None)
	add("chair", "chair")
	for stem in kenney_stems:
		safe = safe_stem(stem)
		if safe in ("cardboardBoxClosed", "chair"):
			continue  # already as crate/chair
		add(safe, stem)

	for file_stem, src_stem in ordered:
		if src_stem is None:
			verts, faces, size_vox = make_barrel()
			family = "wood"
		else:
			src_path = models / f"{src_stem}.obj"
			if not src_path.is_file():
				# Kenney sometimes has spaces in names.
				alt = list(models.glob(src_stem + "*.obj"))
				if not alt:
					print("SKIP missing", src_stem)
					continue
				src_path = alt[0]
			verts, faces = load_obj(src_path)
			verts, size_vox = fit_voxel_footprint(verts, m_per_u)
			family = family_for(src_stem)
		aabb = aabb_of(verts, size_vox)
		write_obj(OUT_PROPS / f"{file_stem}.obj", verts, faces, size_vox)
		entries.append(
			{
				"stem": file_stem,
				"family": family,
				"walk_through": walk_through(file_stem, family),
				"size": size_vox,
				"aabb": aabb,
			}
		)
		print(f"  {file_stem}: {size_vox[0]}x{size_vox[1]}x{size_vox[2]} vox")

	write_catalog_gd(entries)
	last = PROP_FIRST + len(entries) - 1
	patch_voxel_material(len(entries), last)
	patch_materials_rs(len(entries), last)
	write_credits(len(entries))
	print(
		f"DONE {len(entries)} props  ids {PROP_FIRST}..{last}  "
		f"FOOTPRINT={last + 1} COUNT={last + 2}"
	)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())

#!/usr/bin/env python3
"""Build the prop kit from three Kenney CC0 packs (CC0) + authored barrel.

Writes:
  assets/city/props/<stem>.obj     — meshes in voxel units (may span many cells)
  assets/city/props/CREDITS.txt
  scripts/city/room_prop_catalog.gd — ID table, families, sizes, collision AABBs
  patches COUNT in voxel_material.gd + materials.rs (PROP_FIRST..PROP_FOOTPRINT)

Packs are emitted in PACKS order and Furniture stays first, so adding an outdoor
pack appends ids instead of renumbering the indoor kit.

Skips Kenney architectural fillers (walls/floors/doorways) — those are city voxels.

Scale: each pack maps a known model to a known height; city voxels are 0.5 m.

  python tools/gen_room_prop_catalog.py --list   # inventory the packs, write nothing
  python tools/gen_room_prop_catalog.py          # regenerate meshes + catalog
"""

from __future__ import annotations

import argparse
import math
import re
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "tools" / "_prop_src"
OUT_PROPS = ROOT / "assets" / "city" / "props"
CATALOG_GD = ROOT / "scripts" / "city" / "room_prop_catalog.gd"
VOXEL_MAT_GD = ROOT / "scripts" / "city" / "voxel_material.gd"
MATERIALS_RS = ROOT / "native" / "city_voxel" / "src" / "materials.rs"

## First prop id. Everything below it is a hand-written block material.
PROP_FIRST = 76
## Hard ceiling on the material id space. The voxel type channel is 16-bit, but the
## navigation pipeline is not: `Solidity::class_of` takes a u8, the terrain copy the
## nav bake reads is one byte per cell, and `NavSolidity.TABLE_SIZE` says so. An id
## past this would alias onto another material's passability and quietly move a wall.
MAT_ID_LIMIT = 256
VOXEL_M = 0.5
MARGIN_VOX = 0.04


@dataclass(frozen=True)
class Pack:
	"""One CC0 source archive and the rules for what we take out of it."""

	name: str
	url: str
	zip_name: str
	## (stem, height in metres) the whole pack is scaled by.
	anchor: tuple[str, float]
	## Cap per axis in voxel cells, so one prop cannot claim half a room.
	max_axis: int
	## Empty means "everything the skips leave" — only Furniture takes a whole pack.
	## Otherwise exactly these sanitized stems, so `--list` stays the shopping list.
	allow_exact: frozenset[str]
	skip_prefixes: tuple[str, ...]
	skip_exact: frozenset[str]
	## Source stem -> catalog stem, for names that collide or read badly.
	rename: dict[str, str]
	## Outdoor packs get the size-aware walk-through rule instead of the indoor one.
	outdoor: bool


## Kenney Furniture — the indoor kit. Ids 76.. stay pinned to this order, so this
## pack must remain first and its selection rules must not change.
FURNITURE = Pack(
	name="furniture",
	url="https://opengameart.org/sites/default/files/kenney_furniturePack.zip",
	zip_name="kenney_furniturePack.zip",
	anchor=("chair", 1.0),
	max_axis=6,
	allow_exact=frozenset(),
	skip_prefixes=("wall", "floor", "doorway", "paneling"),
	skip_exact=frozenset({"doorwayFront", "doorwayOpen"}),
	rename={},
	outdoor=False,
)

## Kenney Graveyard — the structure of a formal garden: iron railings and gates,
## pillars, urns, lanterns, statuary. Also dresses the graveyard district.
GRAVEYARD = Pack(
	name="graveyard",
	url="https://opengameart.org/sites/default/files/kenney_graveyard-kit_5.0.zip",
	zip_name="kenney_graveyard-kit_5.0.zip",
	anchor=("ironFence", 1.6),
	max_axis=8,
	allow_exact=frozenset(
		{
			# Railings and their posts — the outer line of a formal garden.
			"ironFence",
			"ironFenceBorder",
			"ironFenceBorderColumn",
			"ironFenceBorderGate",
			# Verticals to punctuate bed corners and axis ends.
			"pillarLarge",
			"pillarObelisk",
			"pillarSmall",
			"urnRound",
			"urnSquare",
			# Lighting along the walks.
			"lanternGlass",
			"lightpostSingle",
			# Seating and low walls.
			"bench",
			"stoneWall",
			"stoneWallColumn",
			# Graveyard district dressing, free with the pack.
			"grave",
			"graveBorder",
			"gravestoneBevel",
			"gravestoneCross",
			"gravestoneRound",
			"gravestoneWide",
			"cross",
			"crossColumn",
			"altarStone",
			"fireBasket",
		}
	),
	skip_prefixes=(),
	skip_exact=frozenset(),
	## Furniture already owns `bench`, and this one is a cast stone seat anyway.
	rename={"bench": "benchStone"},
	outdoor=True,
)

## Kenney Nature — the planting: flowers, bushes, grass, rocks, stumps, and the
## small conical trees that stand in for clipped topiary.
NATURE = Pack(
	name="nature",
	url="https://opengameart.org/sites/default/files/Nature%20Kit%20%282.1%29.zip",
	zip_name="kenney_nature-kit.zip",
	anchor=("flower_purpleA", 0.45),
	max_axis=8,
	allow_exact=frozenset(
		{
			# Bed filling. Three colours in two shapes each: a formal bed is planted in
			# blocks of one bloom, so a third shape per colour would never be seen.
			"flower_purpleA",
			"flower_purpleB",
			"flower_redA",
			"flower_redB",
			"flower_yellowA",
			"flower_yellowB",
			"grass",
			"grass_large",
			"plant_bush",
			"plant_bushLarge",
			"plant_bushSmall",
			"mushroom_red",
			"mushroom_redGroup",
			# Clipped shapes — cones stand in for topiary.
			"tree_cone",
			"tree_small",
			# Garden ornament.
			"statue_column",
			"statue_head",
			"statue_obelisk",
			"pot_large",
			"pot_small",
			# Kitchen garden.
			"crop_pumpkin",
			"crops_cornStageC",
			"crops_wheatStageB",
			"fence_simple",
			"fence_simpleHigh",
			"fence_simpleLow",
			"fence_gate",
			"fence_corner",
			# Rough ground and park scatter.
			"stump_old",
			"log_stack",
			"rock_smallA",
			"rock_smallB",
			"rock_smallFlatA",
		}
	),
	skip_prefixes=(),
	skip_exact=frozenset(),
	rename={},
	outdoor=True,
)

PACKS: tuple[Pack, ...] = (FURNITURE, GRAVEYARD, NATURE)

## Props whose mesh reads along one axis. Each gets a Y-rotated `<stem>_z` twin,
## because the block library has one mesh per id and no per-voxel rotation.
ROTATE_KEYWORDS = ("fence", "bench", "gate", "railing", "wall", "log")

## Authored extras not in any pack (file stem, family, pack name it is credited to).
AUTHORED: list[tuple[str, str]] = [
	("barrel", "wood"),
]


def family_for(stem: str, outdoor: bool) -> str:
	s = stem.lower()
	## Iron before metal: a lantern is wrought, a microwave is a white good.
	if any(
		k in s for k in ("ironfence", "lantern", "railing", "chain", "lightpost", "basket")
	):
		return "iron"
	if any(
		k in s
		for k in (
			"flower",
			"grass",
			"mushroom",
			"bush",
			"hedge",
			"tree",
			"crop",
			"plant",
			"potted",
		)
	):
		return "foliage"
	if any(
		k in s
		for k in (
			"pillar",
			"urn",
			"statue",
			"grave",
			"crypt",
			"obelisk",
			"column",
			"cross",
			"altar",
			"rock",
			"stone",
		)
	):
		return "stone"
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
	if any(k in s for k in ("toilet", "bathtub", "shower", "sink", "mirror", "pot_")):
		return "ceramic"
	## A paling fence and a walnut sideboard are not the same timber. Indoor wood is dark
	## and lives under a lamp; outdoors that same surface is a black bar on a lawn.
	return "timber" if outdoor else "wood"


def walk_through_indoor(stem: str, family: str) -> bool:
	s = stem.lower()
	if family == "foliage":
		return True
	if any(k in s for k in ("lamp", "plant", "pillow", "rug", "books", "bear")):
		return True
	return False


def walk_through_outdoor(stem: str, family: str, size: tuple[int, int, int]) -> bool:
	"""Outdoors only ground cover is passable. A topiary or a railing is the garden's
	wall, and walking through a headstone would read as a bug."""
	s = stem.lower()
	## Scatter you step through — collision on these is how walkers get stuck in beds.
	if any(
		k in s
		for k in (
			"flower",
			"grass",
			"mushroom",
			"bush",
			"rock_small",
			"stump",
		)
	):
		return True
	if family != "foliage":
		return False
	## Ankle-high planting whatever its spread, or a single stem up to a metre.
	return size[1] <= 1 or (max(size[0], size[2]) <= 1 and size[1] <= 2)


def pack_dir(pack: Pack) -> Path:
	return SRC / pack.name


def ensure_pack(pack: Pack) -> Path:
	"""Download + extract once, then return the directory holding the OBJ models."""
	root = pack_dir(pack)
	models = find_models_dir(root)
	if models is not None:
		return models
	root.mkdir(parents=True, exist_ok=True)
	archive = SRC / pack.zip_name
	archive.parent.mkdir(parents=True, exist_ok=True)
	if not archive.is_file():
		print(f"GET {pack.url}")
		req = urllib.request.Request(pack.url, headers={"User-Agent": "CityProps/1.0"})
		with urllib.request.urlopen(req, timeout=300) as resp:
			archive.write_bytes(resp.read())
	with zipfile.ZipFile(archive) as zf:
		zf.extractall(root)
	models = find_models_dir(root)
	if models is None:
		raise RuntimeError(f"{pack.name}: no .obj files in {root}")
	return models


def find_models_dir(root: Path) -> Path | None:
	"""Directory holding the most .obj files, preferring an explicit OBJ folder."""
	if not root.is_dir():
		return None
	counts: dict[Path, int] = {}
	for p in root.rglob("*.obj"):
		counts[p.parent] = counts.get(p.parent, 0) + 1
	if not counts:
		return None
	return max(counts, key=lambda d: (("obj" in d.name.lower()), counts[d]))


def load_obj(path: Path) -> tuple[list[list[float]], list[list[int]]]:
	verts: list[list[float]] = []
	faces: list[list[int]] = []
	for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
		if line.startswith("v "):
			p = line.split()
			verts.append([float(p[1]), float(p[2]), float(p[3])])
		elif line.startswith("f "):
			idx = [int(t.split("/")[0]) for t in line.split()[1:]]
			if any(i < 0 for i in idx):
				raise RuntimeError(f"{path}: relative face indices are not supported")
			idx = [i - 1 for i in idx]
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


def anchor_meters_per_unit(pack: Pack, models: Path) -> float:
	stem, target_m = pack.anchor
	path = find_source(models, stem)
	if path is None:
		raise RuntimeError(f"{pack.name}: scale anchor {stem}.obj not found in {models}")
	verts, _ = load_obj(path)
	_lo, _hi, size = bounds(verts)
	return target_m / size[1]


def find_source(models: Path, stem: str) -> Path | None:
	"""Source OBJ whose sanitized stem matches, so kebab and spaced names resolve."""
	want = safe_stem(stem)
	for p in sorted(models.glob("*.obj")):
		if safe_stem(p.stem) == want:
			return p
	return None


def fit_voxel_footprint(
	verts: list[list[float]], m_per_u: float, max_axis: int
) -> tuple[list[list[float]], tuple[int, int, int]]:
	"""Uniform source→voxel scale; integer footprint is the ceil of the scaled AABB."""
	lo, _hi, size_k = bounds(verts)
	scale = m_per_u / VOXEL_M
	size_v = [size_k[i] * scale for i in range(3)]
	nx = max(1, min(max_axis, int(math.ceil(size_v[0] - 1e-4))))
	ny = max(1, min(max_axis, int(math.ceil(size_v[1] - 1e-4))))
	nz = max(1, min(max_axis, int(math.ceil(size_v[2] - 1e-4))))
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


def rotate_y90(
	verts: list[list[float]], size_vox: tuple[int, int, int]
) -> tuple[list[list[float]], tuple[int, int, int]]:
	"""Quarter turn about Y inside the footprint box. Determinant is +1, so the
	face winding the loader produced still faces outward."""
	nx, ny, nz = size_vox
	out = [[v[2], v[1], float(nx) - v[0]] for v in verts]
	return out, (nz, ny, nx)


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


def select_stems(pack: Pack, models: Path) -> list[str]:
	stems: list[str] = []
	found: set[str] = set()
	for p in sorted(models.glob("*.obj")):
		stem = p.stem
		safe = safe_stem(stem)
		low = safe.lower()
		found.add(safe)
		if safe in pack.skip_exact or stem in pack.skip_exact:
			continue
		if any(low.startswith(pref.lower()) for pref in pack.skip_prefixes):
			continue
		if pack.allow_exact and safe not in pack.allow_exact:
			continue
		stems.append(stem)
	## A silently missing pick would just quietly shrink the garden palette.
	missing = sorted(pack.allow_exact - found)
	if missing:
		raise RuntimeError(f"{pack.name}: picked stems not in the pack: {missing}")
	return stems


def safe_stem(stem: str) -> str:
	"""kebab / spaced / punctuated source names to one camelCase identifier."""
	parts = [p for p in re.split(r"[^A-Za-z0-9_]+", stem.strip()) if p]
	if not parts:
		return ""
	return parts[0] + "".join(p[:1].upper() + p[1:] for p in parts[1:])


def wants_rotation(stem: str) -> bool:
	s = stem.lower()
	return any(k in s for k in ROTATE_KEYWORDS)


def write_catalog_gd(entries: list[dict]) -> None:
	lines = [
		"## AUTO-GENERATED by tools/gen_room_prop_catalog.py — do not edit by hand.",
		"## Prop ID table: VoxelMaterial.PROP_FIRST + index.",
		"class_name RoomPropCatalog",
		"extends RefCounted",
		"",
		"const PROP_MESH_DIR := \"res://assets/city/props/\"",
		f"const PROP_FIRST := {PROP_FIRST}",
		f"const PROP_COUNT := {len(entries)}",
		f"const PROP_LAST := {PROP_FIRST + len(entries) - 1}",
		"## Suffix of the quarter-turned twin of an axis-aligned prop.",
		"const ROT_SUFFIX := \"_z\"",
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
		'''
## stem -> id, built once. Placement loops ask for props by name every few voxels,
## and a linear scan of the whole catalog per lookup showed up in bake profiles.
static var _by_stem: Dictionary = {}


static func _index() -> Dictionary:
	if _by_stem.is_empty():
		for i in range(ENTRIES.size()):
			_by_stem[String(ENTRIES[i]["stem"])] = PROP_FIRST + i
	return _by_stem


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


static func walk_through_of(id: int) -> bool:
	var e := entry(id)
	return bool(e.get("walk_through", false))


static func mesh_path(id: int) -> String:
	return PROP_MESH_DIR + stem_of(id) + ".obj"


static func kit_names() -> PackedStringArray:
	var out := PackedStringArray()
	for e in ENTRIES:
		out.append(String(e["stem"]))
	return out


static func has_stem(stem: String) -> bool:
	return _index().has(stem)


## The quarter-turned twin, or the same stem when the prop has none.
static func rotated_stem(stem: String) -> String:
	var twin := stem + ROT_SUFFIX
	return twin if has_stem(twin) else stem


## Twin whose mesh runs along Z when `along_x` is false. Props without a twin are
## symmetric enough to stand either way.
static func oriented_stem(stem: String, along_x: bool) -> String:
	return stem if along_x else rotated_stem(stem)


static func find_stem(stem: String) -> int:
	return int(_index().get(stem, 0))


static func id_for_stem(stem: String) -> int:
	var id := find_stem(stem)
	if id < PROP_FIRST:
		push_error("RoomPropCatalog.id_for_stem: unknown %s" % stem)
		return 0
	return id
'''.strip()
	)
	CATALOG_GD.write_text("\n".join(lines) + "\n", encoding="utf-8")
	print(f"Wrote {CATALOG_GD} ({len(entries)} props)")


def patch_voxel_material(count: int, last: int) -> None:
	text = VOXEL_MAT_GD.read_text(encoding="utf-8")
	pattern = re.compile(
		r"## Room prop kit.*?const COUNT := \d+",
		re.DOTALL,
	)
	footprint = last + 1
	door = footprint + 1
	arena_shell = door + 1
	total = arena_shell + 1
	replacement = (
		"## Room prop kit — see RoomPropCatalog / tools/gen_room_prop_catalog.py.\n"
		f"const PROP_FIRST := {PROP_FIRST}\n"
		f"const PROP_LAST := {last}\n"
		f"const PROP_COUNT := {count}\n"
		"## Invisible solid filler for multi-cell prop footprints (nav / occupancy).\n"
		f"const PROP_FOOTPRINT := {footprint}\n"
		"## Closed door plug — solid barrier in a doorway clear (E-toggle; open restores AIR).\n"
		f"const DOOR := {door}\n"
		"## Arena pit walls / undercroft / lift shafts — looks like masonry, never digs away.\n"
		f"const ARENA_SHELL := {arena_shell}\n"
		"## Legacy aliases (first kit) — prefer RoomPropCatalog.id_for_stem.\n"
		"const PROP_CRATE := PROP_FIRST\n"
		"const PROP_BARREL := PROP_FIRST + 1\n"
		"const PROP_CHAIR := PROP_FIRST + 2\n"
		f"const COUNT := {total}"
	)
	if not pattern.search(text):
		raise RuntimeError(f"{VOXEL_MAT_GD}: room prop block not found")
	text = pattern.sub(replacement, text)
	VOXEL_MAT_GD.write_text(text, encoding="utf-8")
	print(f"Patched {VOXEL_MAT_GD} COUNT={total} FOOTPRINT={footprint}")


def patch_materials_rs(last: int) -> None:
	footprint = last + 1
	door = footprint + 1
	arena_shell = door + 1
	total = arena_shell + 1
	text = MATERIALS_RS.read_text(encoding="utf-8")
	block = re.compile(
		r"pub const PROP_FIRST: i32 = \d+;.*?pub const COUNT: i32 = \d+;", re.DOTALL
	)
	## Compared against the anchor, not against the result: a run that only moves a prop
	## between families writes the same ids back, and "nothing to change" is not "the file
	## no longer has an id block in it".
	if not block.search(text):
		raise RuntimeError(f"{MATERIALS_RS}: prop id block not found")
	patched = block.sub(
		(
			f"pub const PROP_FIRST: i32 = {PROP_FIRST};\n"
			f"#[allow(dead_code)]\n"
			f"pub const PROP_LAST: i32 = {last};\n"
			f"#[allow(dead_code)]\n"
			f"pub const PROP_FOOTPRINT: i32 = {footprint};\n"
			f"#[allow(dead_code)]\n"
			f"pub const DOOR: i32 = {door};\n"
			f"#[allow(dead_code)]\n"
			f"pub const ARENA_SHELL: i32 = {arena_shell};\n"
			f"pub const COUNT: i32 = {total};"
		),
		text,
	)
	MATERIALS_RS.write_text(patched, encoding="utf-8")
	print(f"Patched {MATERIALS_RS} COUNT={total}")


def write_credits(n: int, per_pack: dict[str, int]) -> None:
	OUT_PROPS.mkdir(parents=True, exist_ok=True)
	counts = ", ".join(f"{k} {v}" for k, v in per_pack.items())
	(OUT_PROPS / "CREDITS.txt").write_text(
		f"""Prop meshes (multi-cell voxel footprints) — {n} pieces ({counts})

City voxels are {VOXEL_M} m. Each pack is scaled by one anchor model:
{chr(10).join(f"- {p.name}: {p.anchor[0]} -> {p.anchor[1]} m" for p in PACKS)}

Sources (all CC0 1.0, OpenGameArt mirrors, scaled by tools/gen_room_prop_catalog.py)
- Kenney Furniture Kit — https://kenney.nl/assets/furniture-kit
- Kenney Graveyard Kit — https://kenney.nl/assets/graveyard-kit
- Kenney Nature Kit — https://kenney.nl/assets/nature-kit
- barrel.obj — project-authored lathed cylinder

Stems ending in _z are quarter-turned copies generated here, because the voxel
block library has one mesh per id and no rotation.

Regenerate: python tools/gen_room_prop_catalog.py
""",
		encoding="utf-8",
	)


def list_packs() -> int:
	for pack in PACKS:
		models = ensure_pack(pack)
		m_per_u = anchor_meters_per_unit(pack, models)
		all_objs = sorted(models.glob("*.obj"))
		taken = {safe_stem(s) for s in select_stems(pack, models)}
		print(
			f"\n== {pack.name}: {len(all_objs)} models, {len(taken)} selected, "
			f"{m_per_u:.4f} m/unit ({models})"
		)
		for p in all_objs:
			safe = safe_stem(p.stem)
			verts, _ = load_obj(p)
			_lo, _hi, size = bounds(verts)
			metres = [size[i] * m_per_u for i in range(3)]
			mark = "+" if safe in taken else " "
			print(
				f" {mark} {safe:34s} {metres[0]:5.2f} x {metres[1]:5.2f} x {metres[2]:5.2f} m"
			)
	return 0


def build_order() -> list[tuple[Pack | None, str, str | None]]:
	"""(pack, file_stem, source_stem) in emit order. Furniture first and unchanged."""
	ordered: list[tuple[Pack | None, str, str | None]] = []
	seen: set[str] = set()

	def add(pack: Pack | None, file_stem: str, src_stem: str | None) -> None:
		safe = safe_stem(file_stem)
		if safe in seen:
			## Two packs shipping the same name (Graveyard also has a bench) used to
			## drop the later one on the floor. Prefix instead so nothing vanishes.
			if pack is None:
				raise RuntimeError(f"duplicate authored stem {safe}")
			safe = pack.name + safe[:1].upper() + safe[1:]
			if safe in seen:
				raise RuntimeError(f"duplicate stem {safe}")
		seen.add(safe)
		ordered.append((pack, safe, src_stem))

	for pack in PACKS:
		models = ensure_pack(pack)
		if pack is FURNITURE:
			add(pack, "crate", "cardboardBoxClosed")  # friendly alias
			add(None, "barrel", None)
			add(pack, "chair", "chair")
		for stem in select_stems(pack, models):
			safe = safe_stem(stem)
			if pack is FURNITURE and safe in ("cardboardBoxClosed", "chair"):
				continue  # already as crate/chair
			add(pack, pack.rename.get(safe, safe), stem)
	return ordered


def main() -> int:
	ap = argparse.ArgumentParser(description=__doc__)
	ap.add_argument(
		"--list", action="store_true", help="inventory the packs and write nothing"
	)
	args = ap.parse_args()
	if args.list:
		return list_packs()

	OUT_PROPS.mkdir(parents=True, exist_ok=True)
	for old in OUT_PROPS.glob("*.obj"):
		old.unlink()

	scale: dict[str, float] = {}
	models_of: dict[str, Path] = {}
	for pack in PACKS:
		models = ensure_pack(pack)
		models_of[pack.name] = models
		scale[pack.name] = anchor_meters_per_unit(pack, models)
		print(
			f"{pack.name}: {scale[pack.name]:.4f} m/unit "
			f"({pack.anchor[0]} -> {pack.anchor[1]} m)"
		)

	entries: list[dict] = []
	per_pack: dict[str, int] = {}

	def emit(
		file_stem: str,
		family: str,
		verts: list[list[float]],
		faces: list[list[int]],
		size_vox: tuple[int, int, int],
		outdoor: bool,
		pack_name: str,
	) -> None:
		walk = (
			walk_through_outdoor(file_stem, family, size_vox)
			if outdoor
			else walk_through_indoor(file_stem, family)
		)
		write_obj(OUT_PROPS / f"{file_stem}.obj", verts, faces, size_vox)
		entries.append(
			{
				"stem": file_stem,
				"family": family,
				"walk_through": walk,
				"size": size_vox,
				"aabb": aabb_of(verts, size_vox),
			}
		)
		per_pack[pack_name] = per_pack.get(pack_name, 0) + 1

	for pack, file_stem, src_stem in build_order():
		if src_stem is None:
			verts, faces, size_vox = make_barrel()
			emit(file_stem, "wood", verts, faces, size_vox, False, "authored")
			print(f"  {file_stem}: {size_vox[0]}x{size_vox[1]}x{size_vox[2]} vox")
			continue
		if pack is None:
			raise RuntimeError(f"{file_stem}: source stem without a pack")
		src_path = find_source(models_of[pack.name], src_stem)
		if src_path is None:
			raise RuntimeError(f"{pack.name}: {src_stem}.obj vanished between passes")
		verts, faces = load_obj(src_path)
		verts, size_vox = fit_voxel_footprint(verts, scale[pack.name], pack.max_axis)
		family = family_for(file_stem, pack.outdoor)
		emit(file_stem, family, verts, faces, size_vox, pack.outdoor, pack.name)
		print(f"  {file_stem}: {size_vox[0]}x{size_vox[1]}x{size_vox[2]} vox [{family}]")
		if pack.outdoor and wants_rotation(file_stem) and size_vox[0] != size_vox[2]:
			rot_verts, rot_size = rotate_y90(verts, size_vox)
			emit(
				file_stem + "_z", family, rot_verts, faces, rot_size, pack.outdoor, pack.name
			)
			print(f"  {file_stem}_z: {rot_size[0]}x{rot_size[1]}x{rot_size[2]} vox [turned]")

	## Stale sidecars from props that no longer exist keep showing up in the editor's
	## import list and in asset audits.
	for meta in OUT_PROPS.glob("*.obj.import"):
		if not meta.with_suffix("").is_file():
			meta.unlink()
			print(f"  removed stale {meta.name}")

	last = PROP_FIRST + len(entries) - 1
	## Before anything is patched: a catalog that overflows the id space would compile
	## and bake, and only show up as a district with no navigation in it.
	if last + 3 > MAT_ID_LIMIT:
		raise RuntimeError(
			f"{len(entries)} props need {last + 3} material ids, "
			f"{MAT_ID_LIMIT} is the ceiling — cut {last + 3 - MAT_ID_LIMIT} stems"
		)
	write_catalog_gd(entries)
	patch_voxel_material(len(entries), last)
	patch_materials_rs(last)
	write_credits(len(entries), per_pack)
	print(
		f"DONE {len(entries)} props  ids {PROP_FIRST}..{last}  "
		f"FOOTPRINT={last + 1} DOOR={last + 2} ARENA_SHELL={last + 3} COUNT={last + 4}"
	)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())

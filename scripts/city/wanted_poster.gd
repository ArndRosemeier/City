## One wanted bill pasted flat on a city wall: five metres by ten of old paper, the killer's
## mugshot, and the words that tell a player what to do about it.
##
## The poster is the only part that exists up front. The killer themself is an ordinary
## pedestrian in the suspect's clothes until the player takes a swing at them, at which point
## `CityRoot` promotes them into a body that fights back. Ignore the wall and nothing ever
## happens.
##
## Siting is deliberately picky: only walls that face a world avenue, only footprints that are
## solid all the way across (a doorway or a setback is air, and air rejects the site), and only
## a few per tile, spread out. Windows caught behind a bill are boarded over with the wall's own
## masonry, which is what a plastered-over dead wall looks like.
class_name WantedPoster
extends Node3D

const WantedSuspectScript := preload("res://scripts/city/wanted_suspect.gd")

## Chance a vanilla tile has a killer walking on it. The suspect is the same person city-wide;
## this is the roll for whether *this* tile posts bills about them.
const WANTED_CHANCE := 0.28

## Sheet size in metres. Huge on purpose — this is read from across an avenue.
const SHEET_M := Vector2(5.0, 10.0)
## Bills per tile, and how far apart they have to hang so you meet one every few blocks.
const MAX_PER_TILE := 5
const MIN_SPACING_M := 34.0
## Courses of masonry between the pavement and the bottom edge.
const BASE_RISE_VOX := 3
## How far the paper stands off the wall, to keep it out of the facade's own z-fighting.
const STANDOFF_M := 0.06
## A wall that is mostly glazing is a shopfront, not a hoarding: boarding it over would read
## as damage, so the site is refused instead.
const MIN_OPAQUE_SHARE := 0.55
## Paper stops drawing past this — the sheet is legible far further than the text is.
const VIEW_DISTANCE_M := 220.0

const HEADLINE := "WANTED"
const SUBLINE := "DEAD OR ALIVE"
const WARNING := "DANGEROUS"
const FOOTER := "BY ORDER OF THE CITY WATCH"

## Ink and paper. The sheet texture is procedural and shared by every bill in the world.
const INK := Color(0.17, 0.11, 0.07)
const PAPER := Color(0.85, 0.77, 0.60)
const SHEET_PX := Vector2i(512, 1024)
const LABEL_FONT_PX := 128

const NO_VOX := Vector3i(0x40000000, 0, 0x40000000)

## One pasteable wall patch, in world voxels.
class Site extends RefCounted:
	## Lowest voxel of the run — the bottom "left" corner of the footprint on the wall plane.
	var origin_vox: Vector3i = Vector3i.ZERO
	## Unit step along the wall, away from `origin_vox`.
	var run: Vector3i = Vector3i.ZERO
	## Outward normal of the facade.
	var out_dir: Vector3i = Vector3i.ZERO
	## Footprint size in voxels: x along `run`, y up.
	var span: Vector2i = Vector2i.ZERO
	## Lot the wall belongs to, for tests and logging.
	var lot: Rect2i = Rect2i()

	func middle_vox() -> Vector3i:
		return (
			origin_vox
			+ run * int(span.x / 2)
			+ Vector3i(0, int(span.y / 2), 0)
		)


## Middle of the pasted sheet, in world voxels.
var poster_vox: Vector3i = NO_VOX
## Lot the poster hangs on.
var lot_rect: Rect2i = Rect2i()
## Panes swallowed by the paper and boarded over with the wall's own material.
var panes_boarded: int = 0

static var _sheet_tex: ImageTexture = null


# --------------------------------------------------------------------------------- siting


## Every wall on this tile worth pasting a bill on, already thinned to `MAX_PER_TILE` and
## spaced out. Empty when the tile rolled no killer, or offered no avenue wall tall and blank
## enough to take a ten-metre sheet.
static func pick_sites(
	dseed: int,
	theme_id: int,
	buildings: Dictionary,
	planner: DistrictPlanner,
	brush: CityBrush,
	voxel_size: float
) -> Array[Site]:
	if not posts_bills(dseed, theme_id):
		return [] as Array[Site]
	return sites_on_tile(dseed, buildings, planner, brush, voxel_size)


## Whether this tile posts bills at all: the theme gate and the roll, with no geometry in it.
static func posts_bills(dseed: int, theme_id: int) -> bool:
	if not AlchemyLabSite.is_vanilla_theme(theme_id):
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(dseed) ^ 0x0AF7ED
	return rng.randf() < WANTED_CHANCE


## The walls themselves, whatever this tile rolled. Separate from the roll so the geometry can
## be checked against real baked districts without waiting for a 28% coin to land.
static func sites_on_tile(
	dseed: int,
	buildings: Dictionary,
	planner: DistrictPlanner,
	brush: CityBrush,
	voxel_size: float
) -> Array[Site]:
	var out: Array[Site] = []
	if brush == null:
		push_error("WantedPoster.sites_on_tile: brush is null")
		return out
	if planner == null:
		push_error("WantedPoster.sites_on_tile: planner is null")
		return out
	if buildings.is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(dseed) ^ 0x5177E5
	var span := Vector2i(
		maxi(int(ceil(SHEET_M.x / maxf(voxel_size, 0.01))), 2),
		maxi(int(ceil(SHEET_M.y / maxf(voxel_size, 0.01))), 2)
	)
	var candidates: Array[Site] = []
	for building: BuildingInterior in _unique_buildings(buildings):
		for side in _avenue_sides(building, buildings, planner):
			var site := _wall_site(building, side, span, brush)
			if site != null:
				candidates.append(site)
	if candidates.is_empty():
		return out
	## Shuffled by the tile seed so the same lots do not always carry the bills, then thinned
	## by distance so two of them never end up on the same corner.
	_shuffle(candidates, rng)
	var spacing_vox := MIN_SPACING_M / maxf(voxel_size, 0.01)
	for site in candidates:
		if out.size() >= MAX_PER_TILE:
			break
		var mid := site.middle_vox()
		var clear := true
		for taken: Site in out:
			var other := taken.middle_vox()
			var d := Vector2(mid.x - other.x, mid.z - other.z).length()
			if d < spacing_vox:
				clear = false
				break
		if clear:
			out.append(site)
	return out


## Distinct buildings behind the per-cell index, in a stable order. Merged parcels register
## every cell they cover, so the raw dictionary lists the same lot several times.
static func _unique_buildings(buildings: Dictionary) -> Array[BuildingInterior]:
	var seen: Dictionary = {}
	var out: Array[BuildingInterior] = []
	for key: Vector2i in buildings.keys():
		var b := buildings[key] as BuildingInterior
		if b == null or b.storeys.is_empty() or seen.has(b):
			continue
		seen[b] = true
		out.append(b)
	out.sort_custom(
		func(a: BuildingInterior, b: BuildingInterior) -> bool:
			var pa := a.lot_rect.position
			var pb := b.lot_rect.position
			return pa.y < pb.y if pa.y != pb.y else pa.x < pb.x
	)
	return out


## Sides of this lot that look onto a world avenue. Side numbering is the planner's:
## 0=+Z, 1=−Z, 2=+X, 3=−X.
static func _avenue_sides(
	building: BuildingInterior, buildings: Dictionary, planner: DistrictPlanner
) -> Array[int]:
	var sides: Array[int] = []
	const STEP: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)
	]
	for key: Vector2i in buildings.keys():
		if buildings[key] != building:
			continue
		for side in range(4):
			if sides.has(side):
				continue
			var n: Vector2i = key + STEP[side]
			if planner.tag_at(n.x, n.y) == LandUse.AVENUE:
				sides.append(side)
	sides.sort()
	return sides


## The best patch on one facade, or null when the wall cannot carry a sheet. Every voxel of
## the footprint has to be there: a doorway, a balcony niche or an upper-storey setback is
## air, and a bill hanging over air is the one thing on the street that looks generated.
static func _wall_site(
	building: BuildingInterior, side: int, span: Vector2i, brush: CityBrush
) -> Site:
	var ground := building.storeys[0]
	## The shell wall stands one voxel outside the storey's clear floor.
	var wall := ground.rect.grow(1)
	var run := Vector3i(1, 0, 0) if side <= 1 else Vector3i(0, 0, 1)
	var out_dir := Vector3i.ZERO
	var first := Vector3i.ZERO
	var length := 0
	var base_y := ground.floor_y + BASE_RISE_VOX
	match side:
		0:
			out_dir = Vector3i(0, 0, 1)
			first = Vector3i(wall.position.x, base_y, wall.end.y - 1)
			length = wall.size.x
		1:
			out_dir = Vector3i(0, 0, -1)
			first = Vector3i(wall.position.x, base_y, wall.position.y)
			length = wall.size.x
		2:
			out_dir = Vector3i(1, 0, 0)
			first = Vector3i(wall.end.x - 1, base_y, wall.position.y)
			length = wall.size.y
		3:
			out_dir = Vector3i(-1, 0, 0)
			first = Vector3i(wall.position.x, base_y, wall.position.y)
			length = wall.size.y
		_:
			push_error("WantedPoster._wall_site: side %d out of range" % side)
			return null
	if length < span.x:
		return null
	## Centre first, then walk outwards: a bill in the middle of a facade reads as posted,
	## one jammed against the corner reads as a texture seam.
	var mid := int((length - span.x) / 2)
	for step in range(length - span.x + 1):
		var offset := mid + (int((step + 1) / 2) * (1 if step % 2 == 1 else -1))
		if offset < 0 or offset > length - span.x:
			continue
		var origin: Vector3i = first + run * offset
		if not _footprint_ok(brush, origin, run, span):
			continue
		var site := Site.new()
		site.origin_vox = origin
		site.run = run
		site.out_dir = out_dir
		site.span = span
		site.lot = building.lot_rect
		return site
	return null


## Solid all the way across, and not so glazed that boarding it would gut a shopfront.
static func _footprint_ok(
	brush: CityBrush, origin: Vector3i, run: Vector3i, span: Vector2i
) -> bool:
	var opaque := 0
	for t in range(span.x):
		for row in range(span.y):
			var v: Vector3i = origin + run * t + Vector3i(0, row, 0)
			var id := brush.get_vox(v)
			if id == VoxelMaterial.AIR:
				return false
			if not _is_pane(id):
				opaque += 1
	var total := span.x * span.y
	return float(opaque) >= float(total) * MIN_OPAQUE_SHARE


static func _is_pane(id: int) -> bool:
	return (
		id == VoxelMaterial.GLASS
		or id == VoxelMaterial.GLASS_LIT
		or id == VoxelMaterial.LAB_WINDOW
	)


static func _shuffle(sites: Array[Site], rng: RandomNumberGenerator) -> void:
	for i in range(sites.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := sites[i]
		sites[i] = sites[j]
		sites[j] = tmp


# ------------------------------------------------------------------------------- pasting


## Board the wall behind the sheet and hang the paper on it. `portrait` is the world's
## mugshot; a null one leaves the frame empty, which only happens after `WantedSuspect` has
## already reported why.
func setup(brush: CityBrush, site: Site, voxel_size: float, portrait: ImageTexture) -> bool:
	if brush == null:
		push_error("WantedPoster.setup: brush is null")
		return false
	if site == null:
		push_error("WantedPoster.setup: site is null")
		return false
	lot_rect = site.lot
	poster_vox = site.middle_vox()
	brush.begin_edit()
	panes_boarded = _board_panes(brush, site)
	brush.end_edit()
	_build_sheet(site, voxel_size, portrait)
	return true


## Glass caught behind the paper becomes the wall's own masonry. Boarding rather than leaving
## it lets the bill read as a plastered-over dead wall instead of a curtain hung over a window,
## and it keeps interior light from glowing through the paper at night.
func _board_panes(brush: CityBrush, site: Site) -> int:
	var fill := _wall_material(brush, site)
	var boarded := 0
	for t in range(site.span.x):
		for row in range(site.span.y):
			var v: Vector3i = site.origin_vox + site.run * t + Vector3i(0, row, 0)
			if not _is_pane(brush.get_vox(v)):
				continue
			brush.set_vox(v, fill)
			boarded += 1
	return boarded


## What this facade is built of: the commonest opaque material under the sheet.
func _wall_material(brush: CityBrush, site: Site) -> int:
	var tally: Dictionary = {}
	var best := VoxelMaterial.BRICK
	var best_n := 0
	for t in range(site.span.x):
		for row in range(site.span.y):
			var v: Vector3i = site.origin_vox + site.run * t + Vector3i(0, row, 0)
			var id := brush.get_vox(v)
			if id == VoxelMaterial.AIR or _is_pane(id):
				continue
			var n := int(tally.get(id, 0)) + 1
			tally[id] = n
			if n > best_n:
				best_n = n
				best = id
	if best_n == 0:
		push_error("WantedPoster: pasted on a wall with no masonry in it at %s" % str(poster_vox))
	return best


# -------------------------------------------------------------------------------- visual


func _build_sheet(site: Site, voxel_size: float, portrait: ImageTexture) -> void:
	var size_m := Vector2(float(site.span.x) * voxel_size, float(site.span.y) * voxel_size)
	global_position = _sheet_origin(site, voxel_size)
	## Local +Z is the readable face, which is also the way `Label3D` looks by default.
	rotation = Vector3(0.0, atan2(float(site.out_dir.x), float(site.out_dir.z)), 0.0)

	var sheet := MeshInstance3D.new()
	sheet.name = "Sheet"
	var quad := QuadMesh.new()
	quad.size = size_m
	sheet.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = sheet_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.roughness = 0.95
	mat.metallic = 0.0
	## Most facades are in their own shade for half the day, and a bill nobody can read is a
	## bill nobody hunts. A whisper of self-light keeps the paper legible without turning it
	## into a lightbox after dark.
	mat.emission_enabled = true
	mat.emission = PAPER
	mat.emission_energy_multiplier = 0.22
	## Both faces drawn: the wall is behind the paper, so the back is never seen, and a
	## culled-away sheet would be a silent placement bug.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	sheet.material_override = mat
	_dress(sheet)
	add_child(sheet)

	if portrait != null:
		var frame := MeshInstance3D.new()
		frame.name = "Portrait"
		var pquad := QuadMesh.new()
		pquad.size = Vector2(size_m.x * 0.62, size_m.y * 0.345)
		frame.mesh = pquad
		var pmat := StandardMaterial3D.new()
		pmat.albedo_texture = portrait
		pmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pmat.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
		pmat.roughness = 0.95
		pmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		frame.material_override = pmat
		frame.position = Vector3(0.0, size_m.y * 0.115, 0.004)
		_dress(frame)
		add_child(frame)

	_add_line(HEADLINE, size_m, 0.385, 0.115)
	_add_line(SUBLINE, size_m, -0.115, 0.052)
	_add_line(WARNING, size_m, -0.235, 0.072)
	_add_line(FOOTER, size_m, -0.385, 0.026)


## World position of the sheet's middle: flush with the outer face of the wall it covers,
## a finger's width proud of it.
func _sheet_origin(site: Site, voxel_size: float) -> Vector3:
	var along := Vector3(site.origin_vox) + Vector3(site.run) * (float(site.span.x) * 0.5)
	var x := along.x
	var z := along.z
	## On the normal axis the sheet sits on the *outer* face of the wall voxel, which is the
	## far side of it when the facade looks towards +X / +Z.
	if site.out_dir.x != 0:
		x = float(site.origin_vox.x) + (1.0 if site.out_dir.x > 0 else 0.0)
	if site.out_dir.z != 0:
		z = float(site.origin_vox.z) + (1.0 if site.out_dir.z > 0 else 0.0)
	var y := float(site.origin_vox.y) + float(site.span.y) * 0.5
	return Vector3(x, y, z) * voxel_size + Vector3(site.out_dir) * STANDOFF_M


## One line of press type. Sizes are fractions of the sheet so the layout survives a
## different voxel size.
func _add_line(text: String, size_m: Vector2, y_frac: float, height_frac: float) -> void:
	var lbl := Label3D.new()
	lbl.name = "Line_%s" % text.substr(0, 8)
	lbl.text = text
	lbl.font_size = LABEL_FONT_PX
	lbl.pixel_size = (size_m.y * height_frac) / float(LABEL_FONT_PX)
	lbl.modulate = INK
	lbl.outline_size = 0
	lbl.shaded = false
	lbl.double_sided = false
	lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	lbl.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	lbl.position = Vector3(0.0, size_m.y * y_frac, 0.008)
	_dress(lbl)
	add_child(lbl)


func _dress(gi: GeometryInstance3D) -> void:
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi.visibility_range_end = VIEW_DISTANCE_M
	gi.visibility_range_end_margin = 0.0
	gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


## Blank paper: fibres, a rubbed edge and a heavy ruled border. One texture for the world —
## every bill is the same print run.
static func sheet_texture() -> ImageTexture:
	if _sheet_tex != null:
		return _sheet_tex
	var img := Image.create(SHEET_PX.x, SHEET_PX.y, false, Image.FORMAT_RGBA8)
	img.fill(PAPER)
	## Fibre blocks rather than per-pixel noise: one paint call per 4×4 keeps the one-off cost
	## down and still breaks up the flat fill at arm's length.
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x9A57E
	for by in range(0, SHEET_PX.y, 4):
		for bx in range(0, SHEET_PX.x, 4):
			var shade := rng.randf_range(-0.035, 0.035)
			## Rubbed, dirtier towards the edges.
			var edge := maxf(
				absf(float(bx) / float(SHEET_PX.x) - 0.5),
				absf(float(by) / float(SHEET_PX.y) - 0.5)
			)
			var dim := clampf((edge - 0.34) * 0.55, 0.0, 0.18)
			img.fill_rect(
				Rect2i(bx, by, 4, 4),
				Color(
					clampf(PAPER.r + shade - dim, 0.0, 1.0),
					clampf(PAPER.g + shade - dim * 1.1, 0.0, 1.0),
					clampf(PAPER.b + shade - dim * 1.2, 0.0, 1.0),
					1.0
				)
			)
	## Everything below is in fractions of the sheet, so the print survives a change of
	## resolution. Image rows run from the top, which is why a label at `y_frac` lines up
	## with `(0.5 - y_frac)` here.
	var w := SHEET_PX.x
	var h := SHEET_PX.y
	var heavy := maxi(int(round(float(w) * 0.02)), 2)
	var light := maxi(int(round(float(w) * 0.008)), 1)
	var rule := maxi(int(round(float(h) * 0.003)), 1)
	var inset := int(round(float(w) * 0.023))
	_ink_frame(img, Rect2i(inset, inset, w - inset * 2, h - inset * 2), heavy)
	var inner := int(round(float(w) * 0.0625))
	_ink_frame(img, Rect2i(inner, inner, w - inner * 2, h - inner * 2), light)
	var margin := int(round(float(w) * 0.117))
	img.fill_rect(Rect2i(margin, int(float(h) * 0.191), w - margin * 2, rule), INK)
	var box_x := int(float(w) * 0.164)
	_ink_frame(
		img,
		Rect2i(box_x, int(float(h) * 0.203), w - box_x * 2, int(float(h) * 0.367)),
		light
	)
	img.fill_rect(Rect2i(margin, int(float(h) * 0.578), w - margin * 2, rule), INK)
	img.fill_rect(Rect2i(margin, int(float(h) * 0.836), w - margin * 2, rule), INK)
	_sheet_tex = ImageTexture.create_from_image(img)
	return _sheet_tex


static func _ink_frame(img: Image, rect: Rect2i, thickness: int) -> void:
	img.fill_rect(Rect2i(rect.position.x, rect.position.y, rect.size.x, thickness), INK)
	img.fill_rect(
		Rect2i(rect.position.x, rect.end.y - thickness, rect.size.x, thickness), INK
	)
	img.fill_rect(Rect2i(rect.position.x, rect.position.y, thickness, rect.size.y), INK)
	img.fill_rect(
		Rect2i(rect.end.x - thickness, rect.position.y, thickness, rect.size.y), INK
	)


func has_poster() -> bool:
	return poster_vox != NO_VOX


func poster_world(voxel_size: float) -> Vector3:
	if not has_poster():
		return Vector3.INF
	return Vector3(
		(float(poster_vox.x) + 0.5) * voxel_size,
		(float(poster_vox.y) + 0.5) * voxel_size,
		(float(poster_vox.z) + 0.5) * voxel_size
	)


## Where to go looking for the killer: the street outside the wall the bill is on. The crowd
## marks whoever is nearest, so the hunt starts where the poster is.
func wanted_world(voxel_size: float) -> Vector3:
	return poster_world(voxel_size)

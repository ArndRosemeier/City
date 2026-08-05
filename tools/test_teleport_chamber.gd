## The teleport chamber: its plot, its map, and its launch button.
##
## What is at risk, and therefore checked:
##   - The chamber is the only way off a tile that is not the J picker, so "usually one per
##     district" is not good enough. Exactly one, on every normal theme, or a world can hand
##     the player a district with no console in it.
##   - The 5x5 map is split by hand across eight consoles. A wrong sign or an off-by-one shows
##     up as a neighbour you can never travel to, or as the same tile on two consoles — both
##     silent, both only visible if someone walks the whole ring and reads every panel.
##   - Arming is exclusive. Eight consoles each holding their own highlight would show four
##     destinations lit and launch to whichever the chamber happened to remember.
##   - The pad must swallow a click with nothing armed rather than hopping somewhere.
##   - The roof has to be open over the pad: the launch goes straight up, and a capped chamber
##     would fire the player into the ceiling.
##
## Run: powershell -File tools\run_test.ps1 test_teleport_chamber
extends Node3D

const CityBrushScript := preload("res://scripts/city/city_brush.gd")
const BuildingGrammarScript := preload("res://scripts/city/building_grammar.gd")
const DistrictPlannerScript := preload("res://scripts/city/district_planner.gd")
const TeleportChamberScript := preload("res://scripts/city/teleport_chamber.gd")

const WORLD_SEED := 42
## Every theme that zones lots, and therefore every theme that owes a chamber.
const NORMAL_THEMES: Array[int] = [
	DistrictTheme.CORE_HIGHRISE,
	DistrictTheme.CIVIC_QUARTER,
	DistrictTheme.OLD_TOWN,
	DistrictTheme.GARDEN_RESIDENTIAL,
	DistrictTheme.WATERFRONT_INDUSTRIAL,
]
## Spectacle themes never reach `_assign_zones`, so they must own no chamber either.
const SPECTACLE_THEMES: Array[int] = [
	DistrictTheme.HILL,
	DistrictTheme.GRAVEYARD,
	DistrictTheme.LAKE,
	DistrictTheme.CASTLE,
	DistrictTheme.FRACTAL,
	DistrictTheme.ARENA,
	DistrictTheme.ZOO,
	DistrictTheme.GAMING,
]

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_check_one_lot_per_normal_district()
	_check_spectacle_tiles_have_none()
	_check_map_covers_the_ring_exactly_once()
	await _check_arming_is_exclusive()
	await _check_unarmed_pad_does_not_hop()
	_check_the_roof_is_open_over_the_pad()

	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


# ---------------------------------------------------------------------------
# The plot
# ---------------------------------------------------------------------------

func _check_one_lot_per_normal_district() -> void:
	var tiles := 0
	for theme_id in NORMAL_THEMES:
		for i in range(6):
			var coord := Vector2i(i - 3, i * 2 - 5)
			var planner := _plan(theme_id, coord)
			var found := _teleport_cells(planner)
			if found.size() != 1:
				_fail(
					"FAIL theme %d at %s planned %d teleport chambers, wanted exactly 1"
					% [theme_id, coord, found.size()]
				)
				return
			if found[0] != planner.teleport_lot:
				_fail(
					"FAIL theme %d at %s tagged %s but reports %s"
					% [theme_id, coord, found[0], planner.teleport_lot]
				)
				return
			if planner.teleport_lot == planner.civic_lot:
				_fail("FAIL theme %d at %s put the chamber on the civic lot" % [theme_id, coord])
				return
			## A chamber inside a merged tower plot would never be painted: the parcel anchor
			## builds one tower over all of its cells.
			if planner.tower_parcel_at(planner.teleport_lot.x, planner.teleport_lot.y).size.x > 0:
				_fail(
					"FAIL theme %d at %s swallowed the chamber into a tower parcel"
					% [theme_id, coord]
				)
				return
			tiles += 1
	print("plots: 1 chamber on each of %d normal tiles, never on the civic lot" % tiles)


func _check_spectacle_tiles_have_none() -> void:
	for theme_id in SPECTACLE_THEMES:
		var planner := _plan(theme_id, Vector2i(4, -2))
		var found := _teleport_cells(planner)
		if not found.is_empty():
			_fail("FAIL spectacle theme %d planned %d chambers" % [theme_id, found.size()])
			return
		if planner.teleport_lot != Vector2i(-1, -1):
			_fail("FAIL spectacle theme %d reports a chamber at %s" % [theme_id, planner.teleport_lot])
			return
	print("plots: none of the %d spectacle themes plan a chamber" % SPECTACLE_THEMES.size())


func _plan(theme_id: int, coord: Vector2i) -> DistrictPlanner:
	var planner: DistrictPlanner = DistrictPlannerScript.new()
	planner.theme = DistrictTheme.make(theme_id)
	planner.build(
		DistrictCoord.SIZE_X_VOX,
		DistrictCoord.SIZE_Z_VOX,
		DistrictCoord.district_seed(WORLD_SEED, coord),
		DistrictCoord.CELL_SIZE,
		coord
	)
	return planner


func _teleport_cells(planner: DistrictPlanner) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for z in range(planner.cells_z):
		for x in range(planner.cells_x):
			if planner.tag_at(x, z) == LandUse.TELEPORT_LOT:
				out.append(Vector2i(x, z))
	return out


# ---------------------------------------------------------------------------
# The map
# ---------------------------------------------------------------------------

## The 24 neighbours in the 5x5 block have to appear once each across the eight consoles. A
## missing one is a district you cannot travel to from here; a repeated one is two panels that
## disagree about which is lit.
func _check_map_covers_the_ring_exactly_once() -> void:
	var seen: Dictionary = {}
	for dir in TeleportChamber.SLOT_DIRS:
		var offsets := TeleportChamber.slot_offsets(dir)
		var columns := TeleportChamber.slot_columns(dir)
		if offsets.size() % columns != 0:
			_fail("FAIL console %s has %d panels over %d columns" % [dir, offsets.size(), columns])
			return
		for offset in offsets:
			if seen.has(offset):
				_fail("FAIL %s is on two consoles: %s and %s" % [offset, seen[offset], dir])
				return
			seen[offset] = dir
			## The console a tile lands on is the one you would look at to find it.
			if signi(offset.x) != dir.x or signi(offset.y) != dir.y:
				_fail("FAIL %s sits on the %s console, which faces the wrong way" % [offset, dir])
				return
	for z in range(-2, 3):
		for x in range(-2, 3):
			var offset := Vector2i(x, z)
			if offset == Vector2i.ZERO:
				if seen.has(offset):
					_fail("FAIL a console offers the tile the chamber is standing on")
					return
				continue
			if not seen.has(offset):
				_fail("FAIL %s is on no console — that neighbour is unreachable" % offset)
				return
	if seen.size() != 24:
		_fail("FAIL the consoles carry %d panels, wanted 24" % seen.size())
		return
	print("map: 24 panels over 8 consoles, covering the 5x5 ring once each")


# ---------------------------------------------------------------------------
# Arming and launching
# ---------------------------------------------------------------------------

func _check_arming_is_exclusive() -> void:
	var chamber := await _build_chamber()
	var home := chamber.home_coord()
	## Pick two tiles that are deliberately on different consoles: one straight north, one on
	## the far corner of the south-west block.
	for want in [home + Vector2i(0, -2), home + Vector2i(-2, 2)]:
		var owner: TeleportConsole = null
		for console in chamber.consoles():
			if console.shows_coord(want):
				owner = console
				break
		if owner == null:
			_fail("FAIL no console shows %s" % want)
			chamber.queue_free()
			return
		## Go through the console's own signal, the way a click on the panel does.
		owner.district_chosen.emit(want)
		if chamber.armed_coord() != want:
			_fail("FAIL pressing %s armed %s" % [want, chamber.armed_coord()])
			chamber.queue_free()
			return
		var lit := 0
		for console in chamber.consoles():
			if console.has_selection():
				lit += 1
				if console != owner:
					_fail("FAIL a second console is lit after arming %s" % want)
					chamber.queue_free()
					return
		if lit != 1:
			_fail("FAIL %d consoles are lit after arming %s" % [lit, want])
			chamber.queue_free()
			return
		if not chamber.pad().is_armed():
			_fail("FAIL the pad is dark with %s armed" % want)
			chamber.queue_free()
			return
	## A tile that is off the map disarms rather than arming nothing quietly.
	chamber.arm(home + Vector2i(4, 0))
	if chamber.has_armed() or chamber.pad().is_armed():
		_fail("FAIL a tile outside the 5x5 map still armed the chamber")
	print("arming: one console lit at a time, off-map tiles refused")
	chamber.queue_free()


func _check_unarmed_pad_does_not_hop() -> void:
	var chamber := await _build_chamber()
	var hops: Array[Vector2i] = []
	chamber.hop_requested.connect(func(coord: Vector2i) -> void: hops.append(coord))
	if not chamber.pad().interact_at_world(chamber.pad().global_position):
		_fail("FAIL the pad did not swallow a click, so it can be shot instead")
	if not hops.is_empty():
		_fail("FAIL an unarmed pad launched to %s" % hops[0])
	var want := chamber.home_coord() + Vector2i(2, -1)
	chamber.arm(want)
	chamber.pad().interact_at_world(chamber.pad().global_position)
	if hops.size() != 1 or hops[0] != want:
		_fail("FAIL an armed pad reported %s" % [hops])
	print("pad: silent until a destination is armed, then launches to it")
	chamber.queue_free()


func _build_chamber() -> TeleportChamber:
	var chamber: TeleportChamber = TeleportChamberScript.new()
	add_child(chamber)
	await get_tree().process_frame
	chamber.build(WORLD_SEED, Vector2i(3, -1), Vector3(120.0, 4.0, -60.0), 5.5)
	if chamber.consoles().size() != TeleportChamber.SLOT_DIRS.size():
		_fail("FAIL the chamber stood up %d consoles" % chamber.consoles().size())
	return chamber


# ---------------------------------------------------------------------------
# The room
# ---------------------------------------------------------------------------

## The hop launches straight up off the pad. A capped chamber fires the player into its own
## ceiling, so the column of voxels over the middle of the room has to be air all the way out.
func _check_the_roof_is_open_over_the_pad() -> void:
	var brush: CityBrush = CityBrushScript.new()
	brush.use_offline_volume()
	var grammar: BuildingGrammar = BuildingGrammarScript.new()
	grammar.brush = brush
	grammar.rng = RandomNumberGenerator.new()
	grammar.rng.seed = 7
	grammar.theme = DistrictTheme.make(DistrictTheme.OLD_TOWN)
	grammar.max_height = 60
	var bmin := Vector3i(4, 6, 4)
	var bmax := Vector3i(28, 6, 28)
	grammar.build_for_zone(bmin, bmax, LandUse.TELEPORT_LOT, 0, false, false, false)

	var cx := (bmin.x + bmax.x) / 2
	var cz := (bmin.z + bmax.z) / 2
	var top := bmin.y + BuildingGrammar.TELEPORT_CHAMBER_H_VOX
	for y in range(bmin.y + 2, top + 4):
		var mat := brush.get_vox(Vector3i(cx, y, cz))
		if mat != VoxelMaterial.AIR:
			_fail("FAIL the chamber is capped at y=%d over the pad (material %d)" % [y, mat])
			return
	## The walls still have to be walls, or this is a floor slab and not a room.
	var wall := brush.get_vox(Vector3i(bmin.x, bmin.y + 4, cz))
	if wall == VoxelMaterial.AIR:
		_fail("FAIL the chamber has no west wall at standing height")
		return
	## And there has to be a floor to stand the pad on.
	if brush.get_vox(Vector3i(cx, bmin.y + 1, cz)) == VoxelMaterial.AIR:
		_fail("FAIL the chamber has no floor under the pad")
		return
	if grammar.lot_doorways.is_empty():
		_fail("FAIL the chamber has no street door, so nobody can get in")
		return
	if grammar.built_height_vox <= 0:
		_fail("FAIL the chamber reported no height, so its far-LOD impostor is empty")
	print("room: open to the sky over the pad, walled, floored and with a door")

## Pin the Rust traversal-link bake to the player's climb rules in city_walker.gd.
##
## Mobs cannot raycast for facades the way the player does — remeshed colliders only exist
## near the camera — so their climbs and drops are baked as links. The risk is drift: the
## bake letting a mob climb where `_find_climb_wall()` refuses the player, or the other way
## round. This bakes synthetic single-sector fixtures with the real NavSolidity tables and
## asserts, link by link, that the two agree.
##
## Run: Godot --headless --path . res://tools/test_nav_links.tscn
extends Node

const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")
const NavSolidityScript := preload("res://scripts/city/nav_solidity.gd")
const CityWalkerScript := preload("res://scripts/city/city_walker.gd")

## Voxel edge in metres. The bake, the player and these fixtures all work at this scale.
const VOXEL_SIZE := 0.5
## nav.rs SECTOR. One sector holds every fixture, so a rebuild covers the whole field.
const SECTOR := 28
## Field top, well above the tallest fixture so nothing is clipped by the Y range.
const Y_TOP := 39
const COORD := Vector2i(0, 0)
const PATH_BUDGET := 60000

## `_find_climb_wall()` casts its first probe at chest height. A literal in city_walker.gd,
## repeated here because the coupling this test protects is not an @export.
const CHEST_M := 0.95

## `Profile::base().max_drop` in native/city_voxel/src/nav.rs. Walk edges are baked with that
## profile, so a mob claiming less would refuse edges no link replaces. The player never
## needs a rule to fall off a ledge either — `climb_drop_depth_m` only decides when the
## descent becomes a deliberate climb-down. `_case_terraces()` pins this behaviourally.
const BASE_MAX_DROP_VOX := 4.0

## LINK_* in native/city_voxel/src/nav.rs, checked against the DLL in _ready().
const LINK_CLIMB := 0
const LINK_DROP := 1
const LINK_WALK := 255
## PathStatus::Ok in native/city_voxel/src/nav_world.rs.
const PATH_OK := 0

## NavSolidity.Kind, spelled out because nav_solidity.gd is not in the global class cache
## while it is new.
const KIND_SOLID := 2
const KIND_PARTIAL := 3

const PROFILE_CLIMBER := 1
const PROFILE_WALKER := 2

## The climbable facade: four columns square, ten cells tall, roof surface at 11 voxels.
const FACADE_MIN := Vector3i(4, 1, 12)
const FACADE_MAX := Vector3i(8, 11, 16)
const FACADE_ROOF_Y := 11.0

var _failed := false


## A box of one material, [min, max) in world voxels. Fixtures are lists of these so one
## description feeds both the offline bake and the incremental rebuild.
class Box extends RefCounted:
	var min_v: Vector3i
	var max_v: Vector3i
	var mat: int

	func _init(p_min: Vector3i, p_max: Vector3i, p_mat: int) -> void:
		min_v = p_min
		max_v = p_max
		mat = p_mat


## One baked traversal link, in voxel coordinates.
class Link extends RefCounted:
	var from_pos: Vector3
	var to_pos: Vector3
	var kind: int
	var cost: float

	func _init(p_from: Vector3, p_to: Vector3, p_kind: int, p_cost: float) -> void:
		from_pos = p_from
		to_pos = p_to
		kind = p_kind
		cost = p_cost

	## Take-off column.
	func column() -> Vector2i:
		return Vector2i(int(floor(from_pos.x)), int(floor(from_pos.z)))

	func describe() -> String:
		return (
			"kind=%d (%.1f,%.1f,%.1f)->(%.1f,%.1f,%.1f) cost=%.2f"
			% [
				kind,
				from_pos.x,
				from_pos.y,
				from_pos.z,
				to_pos.x,
				to_pos.y,
				to_pos.z,
				cost,
			]
		)


## The player's climb rules in voxels at character_scale 1.0, read off city_walker.gd so
## retuning the player moves the bake with it.
class PlayerRules extends RefCounted:
	var chest_vox: float
	var head_vox: float
	var min_drop_vox: float
	var max_step_vox: float

	func link_params() -> Dictionary:
		return {
			"climb_chest_vox": chest_vox,
			"climb_head_vox": head_vox,
			"min_drop_vox": min_drop_vox,
		}


func _fail(msg: String) -> void:
	## Both channels: push_error for the editor log, print so a headless run keeps the reason
	## on stdout next to the RESULT line.
	push_error(msg)
	print(msg)
	_failed = true


func _ready() -> void:
	CityVoxelNativeScript.require_loaded()
	var solidity = NavSolidityScript.build()
	var tables: Dictionary = solidity.export_tables()
	_check_fixture_materials(tables)
	var rules := _read_player_rules()
	print(
		(
			"player climb rules: chest %.2f vox, head %.2f vox,"
			+ " climb-down %.2f vox, step %.2f vox"
		)
		% [rules.chest_vox, rules.head_vox, rules.min_drop_vox, rules.max_step_vox]
	)
	if _failed:
		_quit()
		return

	_check_link_ids(tables, rules)
	_case_facades(tables, rules)
	_case_canopy(tables, rules)
	_case_terraces(tables, rules)
	_case_destroyed_facade(tables, rules)
	_case_defaults_mirror_the_player(tables, rules)
	_quit()


func _quit() -> void:
	print("RESULT: %s" % ("FAILED" if _failed else "OK"))
	get_tree().quit(1 if _failed else 0)


func _read_player_rules() -> PlayerRules:
	var walker: CityWalker = CityWalkerScript.new()
	var head_m: float = CHEST_M + maxf(walker.climb_min_wall_m, walker.max_step_height * 2.8)
	var rules := PlayerRules.new()
	rules.chest_vox = CHEST_M / VOXEL_SIZE
	rules.head_vox = head_m / VOXEL_SIZE
	rules.min_drop_vox = walker.climb_drop_depth_m / VOXEL_SIZE
	rules.max_step_vox = walker.max_step_height / VOXEL_SIZE
	walker.free()
	return rules


## The fixtures only mean what the test claims if these materials still classify the way the
## block library says they do.
func _check_fixture_materials(tables: Dictionary) -> void:
	var kind: PackedByteArray = tables["class"]
	var climbable: PackedByteArray = tables["climbable"]
	if kind[VoxelMaterial.BRICK] != KIND_SOLID or climbable[VoxelMaterial.BRICK] != 1:
		_fail("FAIL brick is not a climbable full cell (kind=%d)" % kind[VoxelMaterial.BRICK])
	if kind[VoxelMaterial.CONCRETE] != KIND_SOLID:
		_fail("FAIL concrete ground is not solid (kind=%d)" % kind[VoxelMaterial.CONCRETE])
	if kind[VoxelMaterial.CURB] != KIND_PARTIAL or climbable[VoxelMaterial.CURB] != 0:
		_fail("FAIL curb is not an unclimbable partial cell (kind=%d)" % kind[VoxelMaterial.CURB])


## The link ids this test reasons about must be the ones the DLL bakes.
func _check_link_ids(tables: Dictionary, rules: PlayerRules) -> void:
	var world: Object = _make_world(tables, rules.link_params(), rules)
	var ids := {
		"climb": [int(world.link_climb_id()), LINK_CLIMB],
		"drop": [int(world.link_drop_id()), LINK_DROP],
		"walk": [int(world.link_walk_id()), LINK_WALK],
	}
	for name: String in ids:
		var pair: Array = ids[name]
		if int(pair[0]) != int(pair[1]):
			_fail("FAIL DLL reports LINK_%s=%d, test assumes %d" % [name, pair[0], pair[1]])


# ---------------------------------------------------------------------------
# Cases
# ---------------------------------------------------------------------------


## Four structures on flat ground, each with a take-off column two cells clear of the
## others: a ten cell brick facade the player can climb, a three cell garden wall where the
## head probe finds nothing, a ten cell curb stack (partial collision, so a step and not a
## facade) and a thirty cell tower past the bake's max_climb.
func _facade_boxes() -> Array[Box]:
	var out := _ground()
	out.append(Box.new(FACADE_MIN, FACADE_MAX, VoxelMaterial.BRICK))
	out.append(Box.new(Vector3i(10, 1, 12), Vector3i(14, 4, 16), VoxelMaterial.BRICK))
	out.append(Box.new(Vector3i(16, 1, 12), Vector3i(20, 11, 16), VoxelMaterial.CURB))
	out.append(Box.new(Vector3i(22, 1, 12), Vector3i(26, 31, 16), VoxelMaterial.BRICK))
	return out


## Every column facing the climbable facade, which is where a climb link may take off.
func _facade_takeoffs() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for z in range(FACADE_MIN.z, FACADE_MAX.z):
		out.append(Vector2i(FACADE_MIN.x - 1, z))
		out.append(Vector2i(FACADE_MAX.x, z))
	for x in range(FACADE_MIN.x, FACADE_MAX.x):
		out.append(Vector2i(x, FACADE_MIN.z - 1))
		out.append(Vector2i(x, FACADE_MAX.z))
	return out


func _case_facades(tables: Dictionary, rules: PlayerRules) -> void:
	var world: Object = _make_world(tables, rules.link_params(), rules)
	_insert_fixture(world, _facade_boxes(), tables, rules.link_params())
	var links := _links(world)
	var climbs := _of_kind(links, LINK_CLIMB)
	print("facades: %d links, %d of them climbs" % [links.size(), climbs.size()])

	var takeoffs := _facade_takeoffs()
	if climbs.size() != takeoffs.size():
		_fail(
			"FAIL facades: %d climb links for %d facade columns — %s"
			% [climbs.size(), takeoffs.size(), _describe(climbs)]
		)
	for col: Vector2i in takeoffs:
		var here := _from_column(climbs, col)
		if here.size() != 1:
			_fail("FAIL facades: column %s has %d climb links, want 1" % [col, here.size()])
			continue
		var link: Link = here[0]
		if not is_equal_approx(link.to_pos.y, FACADE_ROOF_Y):
			_fail(
				"FAIL facades: climb from %s lands at y=%.2f, roof is %.2f"
				% [col, link.to_pos.y, FACADE_ROOF_Y]
			)

	## The player's head probe reaches 2.49 m, so a 1.5 m garden wall is a thing to step
	## over, never a facade to climb.
	_expect_no_climb(climbs, Vector2i(9, 14), "a three cell wall is below the head probe")
	## A curb stack is partial collision: the probes pass over every 0.2 m lip.
	_expect_no_climb(climbs, Vector2i(15, 14), "a curb stack offers no facade")
	## Bake-side cap: nothing stops the player climbing 15 m, but a mob will not commit to
	## a facade taller than max_climb.
	_expect_no_climb(climbs, Vector2i(21, 14), "a 30 voxel tower is past max_climb")

	var start := Vector3(2.5, 1.0, 13.5)
	var roof := Vector3(5.5, FACADE_ROOF_Y, 13.5)
	var climber := _path(world, PROFILE_CLIMBER, start, roof)
	if int(climber["status"]) != PATH_OK:
		_fail("FAIL facades: a climber cannot reach the roof (status %d)" % int(climber["status"]))
	elif not _path_uses(climber, LINK_CLIMB):
		_fail("FAIL facades: the climber reached the roof without a climb link")
	var walker := _path(world, PROFILE_WALKER, start, roof)
	if int(walker["status"]) == PATH_OK:
		_fail("FAIL facades: a non-climber must not reach the roof")
	if _path_top_y(walker) >= FACADE_ROOF_Y:
		_fail("FAIL facades: the non-climber's path rises to y=%.2f" % _path_top_y(walker))


## The same facade, roofed over: the tight gap above the roof is not standable and the
## canopy top is behind the ceiling of the take-off column, so the player would climb into
## the underside of the slab and fall off.
func _canopy_boxes() -> Array[Box]:
	var out := _ground()
	out.append(Box.new(FACADE_MIN, FACADE_MAX, VoxelMaterial.BRICK))
	out.append(Box.new(Vector3i(0, 12, 0), Vector3i(SECTOR, 13, SECTOR), VoxelMaterial.CONCRETE))
	return out


func _case_canopy(tables: Dictionary, rules: PlayerRules) -> void:
	var world: Object = _make_world(tables, rules.link_params(), rules)
	_insert_fixture(world, _canopy_boxes(), tables, rules.link_params())

	var takeoff_headroom := _headroom(world, Vector2i(3, 14), 1.0)
	if takeoff_headroom != 11:
		_fail("FAIL canopy: take-off headroom is %d, fixture wants 11" % takeoff_headroom)
	var roof_headroom := _headroom(world, Vector2i(5, 14), FACADE_ROOF_Y)
	if roof_headroom != 1:
		_fail("FAIL canopy: roof headroom is %d, fixture wants 1" % roof_headroom)

	var climbs := _of_kind(_links(world), LINK_CLIMB)
	print("canopy: %d climb links" % climbs.size())
	if not climbs.is_empty():
		_fail(
			"FAIL canopy: %d climb links where the player would hit the slab — %s"
			% [climbs.size(), _describe(climbs)]
		)
	var climber := _path(
		world, PROFILE_CLIMBER, Vector3(2.5, 1.0, 13.5), Vector3(5.5, FACADE_ROOF_Y, 13.5)
	)
	if int(climber["status"]) == PATH_OK:
		_fail("FAIL canopy: a climber must not reach a roof it cannot stand on")


## Three descents of rising depth. A one cell step (0.5 m) leads onto a two cell block
## (1.0 m), so both are walked up and back down rather than linked. The six cell platform
## (3.0 m) is brick, so a climb link gets a mob up and only a drop link gets it off again.
func _terrace_boxes() -> Array[Box]:
	var out := _ground()
	out.append(Box.new(Vector3i(4, 1, 4), Vector3i(14, 2, 24), VoxelMaterial.CONCRETE))
	out.append(Box.new(Vector3i(14, 1, 4), Vector3i(20, 3, 24), VoxelMaterial.CONCRETE))
	out.append(Box.new(Vector3i(22, 1, 4), Vector3i(27, 7, 24), VoxelMaterial.BRICK))
	return out


func _case_terraces(tables: Dictionary, rules: PlayerRules) -> void:
	var world: Object = _make_world(tables, rules.link_params(), rules)
	_insert_fixture(world, _terrace_boxes(), tables, rules.link_params())
	var drops := _of_kind(_links(world), LINK_DROP)
	print("terraces: %d drop links" % drops.size())

	## Nothing may be baked as a descent that the player would treat as a step off a lip.
	for link: Link in drops:
		var depth := link.from_pos.y - link.to_pos.y
		if depth <= rules.min_drop_vox:
			_fail(
				"FAIL terraces: %.2f vox drop is shallower than climb_drop_depth_m (%.2f) — %s"
				% [depth, rules.min_drop_vox, link.describe()]
			)
	## Walking already covers both low lips, so neither is a link.
	for shallow: Vector2i in [Vector2i(4, 10), Vector2i(14, 10)]:
		var here := _from_column(drops, shallow)
		if not here.is_empty():
			_fail("FAIL terraces: column %s got a drop link — %s" % [shallow, _describe(here)])
	## The platform is deeper than walking can express, so its edge carries the link.
	var edge_drops := _from_column(drops, Vector2i(22, 10))
	if edge_drops.size() != 1:
		_fail(
			"FAIL terraces: %d drop links off the platform edge, want 1 — %s"
			% [edge_drops.size(), _describe(edge_drops)]
		)
	elif not is_equal_approx((edge_drops[0] as Link).to_pos.y, 1.0):
		_fail(
			"FAIL terraces: the drop lands at y=%.2f, ground is 1.0"
			% (edge_drops[0] as Link).to_pos.y
		)

	## The platform is only leavable through the link, while the two lips a walk edge already
	## covers must stay walkable — a mob that needed a link there would be stranded, because
	## the bake emits none.
	var off_platform := _path(
		world, PROFILE_CLIMBER, Vector3(24.5, 7.0, 10.5), Vector3(11.5, 1.0, 10.5)
	)
	if int(off_platform["status"]) != PATH_OK:
		_fail("FAIL terraces: no route off the platform (status %d)" % int(off_platform["status"]))
	elif not _path_uses(off_platform, LINK_DROP):
		_fail("FAIL terraces: leaving the platform did not use a drop link")
	var ground := Vector3(1.5, 1.0, 10.5)
	_expect_walk_off(world, "step", Vector3(4.5, 2.0, 10.5), ground)
	_expect_walk_off(world, "block", Vector3(17.5, 3.0, 10.5), ground)


## A descent walking already covers has to stay a route, and stay free of drop links.
func _expect_walk_off(world: Object, label: String, from_vox: Vector3, to_vox: Vector3) -> void:
	var path := _path(world, PROFILE_CLIMBER, from_vox, to_vox)
	if int(path["status"]) != PATH_OK:
		_fail("FAIL terraces: no route off the %s (status %d)" % [label, int(path["status"])])
	elif _path_uses(path, LINK_DROP):
		_fail("FAIL terraces: walking off the %s was baked as a drop" % label)


## The facade with its lower ten cells blasted away, leaving the roof slab floating.
func _hollow_facade_boxes() -> Array[Box]:
	var out := _ground()
	out.append(
		Box.new(
			Vector3i(FACADE_MIN.x, FACADE_MAX.y - 1, FACADE_MIN.z),
			FACADE_MAX,
			VoxelMaterial.BRICK
		)
	)
	return out


func _case_destroyed_facade(tables: Dictionary, rules: PlayerRules) -> void:
	var world: Object = _make_world(tables, rules.link_params(), rules)
	var standing := _ground()
	standing.append(Box.new(FACADE_MIN, FACADE_MAX, VoxelMaterial.BRICK))
	_insert_fixture(world, standing, tables, rules.link_params())

	var before := _of_kind(_links(world), LINK_CLIMB)
	if before.size() != _facade_takeoffs().size():
		_fail(
			"FAIL destruction: %d climb links before the blast, want %d"
			% [before.size(), _facade_takeoffs().size()]
		)
	var roof := Vector3(5.5, FACADE_ROOF_Y, 13.5)
	var start := Vector3(2.5, 1.0, 13.5)
	if int(_path(world, PROFILE_CLIMBER, start, roof)["status"]) != PATH_OK:
		_fail("FAIL destruction: the climber cannot reach the intact roof")

	## Whole-sector box: cells outside it read as solid, so a smaller one would bury the
	## ground around the change. Its height comes from the field, which knows how far above
	## its own top row the climb and jump probes reach.
	var band: Vector2i = world.rebuild_y_range(COORD)
	if band.x != 0 or band.y <= Y_TOP:
		_fail("FAIL destruction: the field wants voxel rows %s for a 0..%d bake" % [str(band), Y_TOP])
		return
	var touched: int = world.rebuild_region(
		COORD,
		Vector3i.ZERO,
		Vector3i(SECTOR, band.y + 1, SECTOR),
		_materials(_hollow_facade_boxes(), band.y + 1),
		1
	)
	if touched != 1:
		_fail("FAIL destruction: rebuild_region touched %d sectors, want 1" % touched)

	var after := _of_kind(_links(world), LINK_CLIMB)
	print("destruction: %d climb links before, %d after" % [before.size(), after.size()])
	if not after.is_empty():
		_fail(
			"FAIL destruction: %d climb links survive on a facade that is gone — %s"
			% [after.size(), _describe(after)]
		)
	## The roof itself must still be there, or the test proved nothing about the facade.
	var roof_headroom := _headroom(world, Vector2i(5, 14), FACADE_ROOF_Y)
	if roof_headroom < 2:
		_fail("FAIL destruction: the roof span went with the facade (headroom %d)" % roof_headroom)
	if int(_path(world, PROFILE_CLIMBER, start, roof)["status"]) == PATH_OK:
		_fail("FAIL destruction: the climber still reaches a roof with no facade under it")


## The Rust defaults are meant to already be the player's numbers. Baking the sensitive
## fixtures with an empty parameter dictionary has to produce the same links, so a default
## drifting away from city_walker.gd fails here rather than in the field.
func _case_defaults_mirror_the_player(tables: Dictionary, rules: PlayerRules) -> void:
	_compare_defaults("facades", _facade_boxes(), tables, rules)
	_compare_defaults("terraces", _terrace_boxes(), tables, rules)


func _compare_defaults(
	label: String, boxes: Array[Box], tables: Dictionary, rules: PlayerRules
) -> void:
	var derived: Object = _make_world(tables, rules.link_params(), rules)
	_insert_fixture(derived, boxes, tables, rules.link_params())
	var defaults: Object = _make_world(tables, {}, rules)
	_insert_fixture(defaults, boxes, tables, {})
	var a := _signature(_links(derived))
	var b := _signature(_links(defaults))
	if a != b:
		_fail(
			(
				"FAIL %s: the Rust link defaults no longer match city_walker.gd"
				+ " (%d links from the player's numbers, %d from the defaults)"
			)
			% [label, a.size(), b.size()]
		)


# ---------------------------------------------------------------------------
# Fixture plumbing
# ---------------------------------------------------------------------------


func _ground() -> Array[Box]:
	var out: Array[Box] = []
	out.append(Box.new(Vector3i.ZERO, Vector3i(SECTOR, 1, SECTOR), VoxelMaterial.CONCRETE))
	return out


func _make_world(tables: Dictionary, link_params: Dictionary, rules: PlayerRules) -> Object:
	var world: Object = CityVoxelNativeScript.make_nav_world()
	world.configure(
		VOXEL_SIZE,
		tables["class"],
		tables["top"],
		tables["destructible"],
		tables["climbable"],
		link_params
	)
	## A mob built like the player: narrower than a cell, four cells tall, curb-height step,
	## and willing to walk off a ledge as far as the bake's own walk edges go.
	var body := {
		"radius_cells": 0,
		"height_cells": 4,
		"max_step_vox": rules.max_step_vox,
		"max_drop_vox": BASE_MAX_DROP_VOX,
		"can_jump": false,
	}
	var climber := body.duplicate()
	climber["can_climb"] = true
	world.register_profile(PROFILE_CLIMBER, climber)
	var walker := body.duplicate()
	walker["can_climb"] = false
	world.register_profile(PROFILE_WALKER, walker)
	return world


func _insert_fixture(
	world: Object, boxes: Array[Box], tables: Dictionary, link_params: Dictionary
) -> void:
	var volume: Object = CityVoxelNativeScript.make_volume()
	for box: Box in boxes:
		volume.fill_box(box.min_v, box.max_v, box.mat)
	var bake: Object = CityVoxelNativeScript.make_nav_bake()
	var baked: bool = bake.bake_from_volume(
		volume,
		Vector3i.ZERO,
		SECTOR,
		SECTOR,
		0,
		Y_TOP,
		tables["class"],
		tables["top"],
		tables["destructible"],
		tables["climbable"],
		link_params
	)
	if not baked:
		_fail("FAIL the nav bake refused a fixture volume")
		return
	if not bool(world.insert_bake(COORD, bake)):
		_fail("FAIL insert_bake refused a fixture field")


## The fixture as the dense Y-major material box rebuild_region reads. `rows` is its height:
## the field's own Y range plus the rows the link probes read above it, which `rebuild_region`
## insists on because everything outside the box reads solid.
func _materials(boxes: Array[Box], rows: int) -> PackedByteArray:
	var size := Vector3i(SECTOR, rows, SECTOR)
	var out := PackedByteArray()
	out.resize(size.x * size.y * size.z)
	out.fill(VoxelMaterial.AIR)
	for box: Box in boxes:
		for z in range(box.min_v.z, box.max_v.z):
			for x in range(box.min_v.x, box.max_v.x):
				for y in range(box.min_v.y, box.max_v.y):
					out[y + x * size.y + z * size.y * size.x] = box.mat
	return out


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------


## Every link in the fixture, converted to voxel coordinates.
func _links(world: Object) -> Array[Link]:
	var centre := Vector3(SECTOR * 0.5, 0.0, SECTOR * 0.5) * VOXEL_SIZE
	var raw: Dictionary = world.debug_links(centre, float(SECTOR) * VOXEL_SIZE)
	var from: PackedVector3Array = raw["from"]
	var to: PackedVector3Array = raw["to"]
	var kind: PackedByteArray = raw["kind"]
	var cost: PackedFloat32Array = raw["cost"]
	if from.size() != to.size() or from.size() != kind.size() or from.size() != cost.size():
		_fail(
			"FAIL debug_links returned ragged arrays (%d/%d/%d/%d)"
			% [from.size(), to.size(), kind.size(), cost.size()]
		)
	var out: Array[Link] = []
	for i in range(from.size()):
		out.append(Link.new(from[i] / VOXEL_SIZE, to[i] / VOXEL_SIZE, int(kind[i]), cost[i]))
	return out


func _of_kind(links: Array[Link], kind: int) -> Array[Link]:
	var out: Array[Link] = []
	for link: Link in links:
		if link.kind == kind:
			out.append(link)
	return out


func _from_column(links: Array[Link], col: Vector2i) -> Array[Link]:
	var out: Array[Link] = []
	for link: Link in links:
		if link.column() == col:
			out.append(link)
	return out


func _expect_no_climb(climbs: Array[Link], col: Vector2i, why: String) -> void:
	var here := _from_column(climbs, col)
	if not here.is_empty():
		_fail("FAIL column %s got a climb link although %s — %s" % [col, why, _describe(here)])


## Sorted link list, so two bakes can be compared as a whole.
func _signature(links: Array[Link]) -> PackedStringArray:
	var out := PackedStringArray()
	for link: Link in links:
		out.append(link.describe())
	out.sort()
	return out


func _describe(links: Array[Link]) -> String:
	var parts := PackedStringArray()
	for link: Link in links:
		parts.append(link.describe())
	return "; ".join(parts)


## Free cells above the span standing at `y_vox` in a column, or -1 when there is none.
func _headroom(world: Object, col: Vector2i, y_vox: float) -> int:
	var centre := Vector3(col.x + 0.5, 0.0, col.y + 0.5) * VOXEL_SIZE
	var raw: Dictionary = world.debug_spans(centre, VOXEL_SIZE)
	var positions: PackedVector3Array = raw["positions"]
	var headroom: PackedByteArray = raw["headroom"]
	for i in range(positions.size()):
		var p := positions[i] / VOXEL_SIZE
		if int(floor(p.x)) == col.x and int(floor(p.z)) == col.y and is_equal_approx(p.y, y_vox):
			return int(headroom[i])
	return -1


func _path(world: Object, profile: int, from_vox: Vector3, to_vox: Vector3) -> Dictionary:
	return world.find_path(profile, from_vox * VOXEL_SIZE, to_vox * VOXEL_SIZE, PATH_BUDGET)


func _path_uses(path: Dictionary, kind: int) -> bool:
	var kinds: PackedByteArray = path["links"]
	for i in range(kinds.size()):
		if int(kinds[i]) == kind:
			return true
	return false


## Highest point of a path, in voxels.
func _path_top_y(path: Dictionary) -> float:
	var points: PackedVector3Array = path["points"]
	var top := -1e30
	for i in range(points.size()):
		top = maxf(top, points[i].y / VOXEL_SIZE)
	return top

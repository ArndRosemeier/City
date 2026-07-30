## Castle district look inspection: boots the live city into a Castle tile and saves the
## views the fortress has to survive — the whole thing from the air, the causeway seen from
## street level, the gatehouse, the bailey, a wall/tower elevation, the Phase 2 interiors
## (the keep from the bailey, the great hall, a stairwell, an ordinary room and the rampart
## from the crown landing), the ditch and its drawbridge, the formal gardens, and the Phase 3
## dungeon: every way down this seed happens to have, a wide hall, a cramped cell, a tall
## vault, a corridor and a flight between levels.
##
## Every file is named for the world seed, because the dungeon's whole point is that two seeds
## differ: run this two or three times over and compare the same view side by side.
##
## Run (-Command, not -File: the -File binder flattens a comma list into one argument):
##   powershell -Command "& '.\tools\run_test.ps1' -Scene shot_castle_district -Rendered
##     -GodotArgs @('--spawn-theme=castle','--city-seed=42')"
extends Node

const VOX := 0.5
## Standing eye height, in metres above the walking surface.
const EYE := 1.7
## Mid-morning: long enough shadows for the plinth's batter and the moat's terraces to
## read, high enough that the meadow is not in the fortress's own shadow.
const SHOT_HOUR := 9.5
## Columns in from a chamber's corner a camera stands, so it is not inside the wall it is
## photographing and has the clearance the chamber's own floor plan promises.
const INSET := 3


## World seed the shots are named for, read back after CityRoot resolved the CLI flag.
var _seed: int = 0
var _city: CityRoot = null
## The tile's hung doors, so every frame can be aimed at the camera it is captured from
## instead of at the player's. Null until the district is found; still null on a tile with no
## castle, which is a state this tool already refuses before it gets that far.
var _doors: CastleDoorPlacer = null


func _ready() -> void:
	var city := CityRoot.new()
	city.city_seed = 42
	add_child(city)
	_city = city

	var deadline := Time.get_ticks_msec() + 120_000
	while city.get_node_or_null("Walker") == null:
		if Time.get_ticks_msec() > deadline:
			push_error("FAIL no walker after 120 s")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	_seed = city.city_seed
	var walker: Node3D = city.get_node_or_null("Walker")
	## The walker is only here to keep voxels meshed around the camera; inside a room its
	## own body is all the frame would contain.
	_hide_meshes(walker)
	_hide_overlays(city)
	_stop_the_clock(city)

	var coord := city.spawn_district_coord
	var theme := DistrictTheme.for_district(city.city_seed, coord)
	print("spawn district %s = %s" % [coord, theme.display_name])
	if theme.id != DistrictTheme.CASTLE:
		push_error("FAIL spawn district is %s, expected Castle" % theme.display_name)
		get_tree().quit(1)
		return

	await _settle(10.0)
	var inst := _spawn_district(city)
	if inst == null:
		push_error("FAIL spawn district instance not loaded")
		get_tree().quit(1)
		return
	var layout := inst.generator.get_castle_layout()
	if layout == null:
		push_error("FAIL the streamed castle district carries no layout")
		get_tree().quit(1)
		return
	print(layout.describe())
	_doors = inst.castle_doors
	if _doors == null:
		push_error("FAIL the streamed castle district hung no doors")
		get_tree().quit(1)
		return
	print("doors: %d hung" % _doors.door_count())

	var deck := float(inst.generator.ground_thickness) * VOX
	var court := float(layout.courtyard_y) * VOX
	var middle := _at(coord, _rect_centre(layout.plateau_rect), layout.courtyard_y)
	var gate_face := _at(
		coord,
		layout.gate_center + layout.gate_dir * (layout.wall_thick + 6),
		layout.courtyard_y
	)
	var foot := _at(coord, layout.causeway_line[0], inst.generator.ground_thickness)
	var bailey := _at(coord, layout.courtyard_center, layout.courtyard_y)

	## Oblique aerial from over the approach, so the causeway, the gatehouse and the far
	## corner towers are all in one frame. Kept inside 120 m: voxels only mesh around the
	## walker, and a camera parked further out than that photographs an empty sky.
	var out := Vector3(layout.gate_dir.x, 0.0, layout.gate_dir.y)
	await _shoot_near(
		walker,
		middle + out * 75.0 + Vector3(45.0, 85.0, 0.0),
		middle,
		_png("aerial")
	)

	## Standing on the meadow at the foot of the ramp, looking up the causeway at the gate.
	await _shoot_near(
		walker,
		foot + out * 16.0 + Vector3(0.0, deck + 1.7, 0.0),
		Vector3(gate_face.x, court + 6.0, gate_face.z),
		_png("approach")
	)

	## Half way up the ramp — the gatehouse and its turrets at eye height.
	await _shoot_near(
		walker,
		foot.lerp(gate_face, 0.55) + Vector3(0.0, 5.0, 0.0),
		Vector3(gate_face.x, court + 5.0, gate_face.z),
		_png("gatehouse")
	)

	## Inside the bailey, looking back at the gatehouse across the courtyard. Well clear of
	## the floor: the walker has to stand at the camera for the voxels here to mesh, and at
	## head height it is the only thing in frame.
	await _shoot_near(
		walker,
		bailey + Vector3(0.0, 8.0, 0.0),
		Vector3(gate_face.x, court + 8.0, gate_face.z),
		_png("courtyard")
	)

	## Outside a corner tower at ground level: the batter of the plinth, the curtain above
	## it, and the tower rising past both.
	var corner := _corner_tower(layout)
	var plateau_mid := _rect_centre(layout.plateau_rect)
	var away := Vector3(
		signf(float(corner.center.x - plateau_mid.x)),
		0.0,
		signf(float(corner.center.y - plateau_mid.y))
	).normalized()
	var tower_at := _at(coord, corner.center, layout.courtyard_y)
	await _shoot_near(
		walker,
		tower_at + away * 55.0 + Vector3(0.0, deck + 12.0, 0.0),
		Vector3(tower_at.x, float(corner.top_y) * VOX * 0.7, tower_at.z),
		_png("elevation")
	)

	## The keep across the bailey. Three-quarter on rather than square, so two faces and the
	## corner turrets read, and so the HUD's energy bar does not sit over the entrance.
	var door := layout.keep_entrance
	var door_out := Vector3(-float(door.axis.x), 0.0, -float(door.axis.y))
	var door_side := Vector3(door_out.z, 0.0, -door_out.x)
	var door_at := _at(coord, door.center, door.floor_y)
	await _shoot_near(
		walker,
		door_at + door_out * 20.0 + door_side * 13.0 + Vector3(0.0, 7.0, 0.0),
		_at(
			coord,
			_rect_centre(layout.keep_rect),
			(layout.courtyard_y + layout.keep_roof_y) / 2
		),
		_png("keep")
	)

	## Standing in the great hall at one gable end, looking down its length. Aimed above
	## eye height so the second storey of the double height is in frame.
	var hall_floor := layout.keep_floor(layout.keep_hall_storey)
	var hall := hall_floor.hall_rect()
	var long_x := hall.size.x >= hall.size.y
	var hall_a := Vector2i(
		hall.position.x + (3 if long_x else hall.size.x / 2),
		hall.position.y + (hall.size.y / 2 if long_x else 3)
	)
	var hall_b := Vector2i(
		hall.end.x - (3 if long_x else hall.size.x / 2),
		hall.end.y - (hall.size.y / 2 if long_x else 3)
	)
	await _shoot_lit(
		walker,
		_stand(coord, hall_a, hall_floor.floor_y),
		_at(coord, hall_b, hall_floor.floor_y)
			+ Vector3(0.0, float(hall_floor.air_h) * VOX * 0.5, 0.0),
		_png("hall"),
		40.0
	)

	## At the foot of a keep flight, level on the middle tread. Aimed at the top instead the
	## frame is all underside of the slab the well is cut through, and aimed from the top it
	## is all well lip.
	var flight := _keep_flight(layout)
	var climb := Vector3(float(flight.dir.x), 0.0, float(flight.dir.y))
	var side := Vector3(float(flight.across.x), 0.0, float(flight.across.y))
	var mid := flight.rise / 2
	await _shoot_lit(
		walker,
		_stand(coord, flight.center_column(0), flight.y_from) - climb * 1.2 + side * 0.6,
		_at(coord, flight.center_column(mid), flight.surface_at(mid) + 1),
		_png("stair"),
		30.0
	)

	## An ordinary room on an upper storey, corner to corner so the span shows.
	var top := layout.keep_floor(layout.keep_top_storey())
	var room := _plain_room(top)
	await _shoot_lit(
		walker,
		_stand(coord, room.position + Vector2i(3, 3), top.floor_y),
		_stand(coord, room.end - Vector2i(3, 3), top.floor_y),
		_png("room"),
		30.0
	)

	## On the crown landing at the head of the ramp, looking along the rampart walk.
	var crown_eye := _stand(
		coord, layout.crown_walk, layout.courtyard_y + layout.wall_height
	)
	var along := _crown_along(layout)
	await _shoot_near(
		walker,
		crown_eye,
		crown_eye + along * 40.0 - Vector3(0.0, 1.0, 0.0),
		_png("rampart")
	)

	await _shoot_moat(walker, coord, layout, deck)
	await _shoot_gardens(walker, coord, layout)
	await _shoot_dungeon(walker, coord, layout)

	print("RESULT: OK")
	get_tree().quit(0)


# ---------------------------------------------------------------------------
# Moat and gardens
# ---------------------------------------------------------------------------

## The ditch from the bank and the crossing from below. Both frames are missing on a seed
## that rolled no moat, which is the record of the roll — same as the dungeon shots.
func _shoot_moat(
	walker: Node3D, coord: Vector2i, layout: CastleLayout, deck: float
) -> void:
	if not layout.has_moat:
		print("moat: none on seed %d" % _seed)
		return
	print("moat: %s" % layout.moat_describe())
	var out := Vector3(layout.gate_dir.x, 0.0, layout.gate_dir.y)
	var side := Vector3(-out.z, 0.0, out.x)
	var edge := _at(coord, layout.causeway_line[layout.causeway_line.size() - 1], 0)
	var span := float(layout.bridge_from + layout.bridge_to) * 0.5 * VOX
	var over := edge + out * span
	## Out on the meadow past the far lip, off the causeway's axis and well above head
	## height, looking down at the bed. A ditch is below the ground it is cut into, so from
	## standing height the near lip hides the whole thing and the frame is a lawn.
	var back := float(layout.moat_width) * VOX + 14.0
	var across := float(layout.moat_width + layout.causeway_hw + 6) * VOX
	await _shoot_near(
		walker,
		over + out * back + side * across + Vector3(0.0, deck + 16.0, 0.0),
		Vector3(over.x, float(layout.moat_bed_y) * VOX, over.z),
		_png("moat")
	)
	## Down in the ditch beside the piers, looking up at the leaf and its winch posts.
	await _shoot_near(
		walker,
		over + side * float(layout.causeway_hw + 6) * VOX
			+ Vector3(0.0, float(layout.moat_bed_y) * VOX + EYE, 0.0),
		Vector3(over.x, deck + float(layout.moat_depth) * VOX + 8.0, over.z),
		_png("drawbridge")
	)


## One plot of each kind, seen down its long axis from just outside the railing. Two
## parterres would be the same picture twice, so only the first of a kind is shot.
func _shoot_gardens(walker: Node3D, coord: Vector2i, layout: CastleLayout) -> void:
	print("gardens: %s" % layout.garden_describe())
	var shot: Dictionary[int, bool] = {}
	for g: CastleGarden in layout.gardens:
		if shot.has(g.kind):
			continue
		shot[g.kind] = true
		var centre := _at(coord, _rect_centre(g.rect), g.surface_y)
		var eye := float(g.surface_y) * VOX + EYE
		var reach := float(g.rect.size.y) * VOX * 0.5
		await _shoot_near(
			walker,
			Vector3(centre.x, eye + 2.5, centre.z - reach - 5.0),
			Vector3(centre.x, eye, centre.z),
			_png("garden_%s" % g.kind_name())
		)


# ---------------------------------------------------------------------------
# Dungeon — Phase 3
# ---------------------------------------------------------------------------

## Every way down this seed rolled, then one of each kind of chamber it has. Which files appear
## is therefore itself a record of the seed, which is the point: a castle with one entrance and
## no tall vault should not photograph like a castle with three and two.
func _shoot_dungeon(walker: Node3D, coord: Vector2i, layout: CastleLayout) -> void:
	print(
		"dungeon: %s, %d chambers, wide=%d small=%d tall=%d, %d flights between levels"
		% [
			layout.dungeon_entry_names(),
			layout.dungeon_vaults.size(),
			layout.dungeon_wide_count(),
			layout.dungeon_small_count(),
			layout.dungeon_tall_count(),
			layout.dungeon_stairs.size(),
		]
	)
	for e: CastleDungeonEntry in layout.dungeon_entries:
		await _shoot_entry(walker, coord, layout, e)

	## Widest chamber of one storey height. A tall one is wide by construction, so excluding
	## them is what makes this shot say something the vault shot does not.
	var wide := _pick_vault(layout, "wide")
	await _shoot_along(
		walker, coord, wide, _png("dungeon_wide"), 55.0, 0.45
	)

	var small := _pick_vault(layout, "small")
	await _shoot_along(
		walker, coord, small, _png("dungeon_cell"), 22.0, 0.5
	)

	## Aimed high up the far wall: what a vault is for is the section, and at eye level a
	## three-storey hall photographs exactly like a one-storey room.
	var tall := _pick_vault(layout, "tall")
	if tall != null:
		await _shoot_along(
			walker, coord, tall, _png("dungeon_vault"), 60.0, 0.85
		)

	## Longest chamber relative to its width — what the plan uses for a passage, since a
	## dungeon corridor here is a room cut thin rather than a separate kind of thing.
	var run := _pick_vault(layout, "long")
	await _shoot_along(
		walker, coord, run, _png("dungeon_corridor"), 45.0, 0.4
	)

	var flight: CastleStair = layout.dungeon_stairs[0]
	await _shoot_flight(walker, coord, flight, _png("dungeon_stair"))


## A way down, seen from the side a body arrives on.
##
## The two routes that surface in the open are shot from a step behind the top tread, looking
## down the shaft. The tower base cannot be: its head stands under the tower with the plate's
## solid mass behind it, and the only place to stand is the passage that reaches it, so that is
## where the camera goes — which is also how a player meets it.
func _shoot_entry(
	walker: Node3D, coord: Vector2i, layout: CastleLayout, e: CastleDungeonEntry
) -> void:
	var st := e.stair
	var climb := Vector3(float(st.dir.x), 0.0, float(st.dir.y))
	var stem := "dungeon_from_%s" % e.kind_name().replace("-", "_")
	if e.kind == CastleDungeonEntry.KIND_TOWER_BASE:
		## The bailey end of the passage rather than its middle: it is four columns wide, and
		## from the middle of it the frame is two walls. Dim, because at arm's length from the
		## passage wall the lamp the open chambers need burns the frame out white.
		await _shoot_lit(
			walker,
			_stand(coord, _far_end(e.chamber_rect, e.head()), layout.courtyard_y),
			_at(coord, e.head(), layout.courtyard_y + 2),
			_png(stem),
			30.0,
			1.4
		)
		return
	await _shoot_lit(
		walker,
		_stand(coord, e.head(), layout.courtyard_y) + climb * 1.2,
		_at(coord, e.foot(), st.y_from + 2),
		_png(stem),
		34.0
	)


## Stands `INSET` in from one end of a chamber and looks at the other, aiming `up` of the way
## up the far wall.
func _shoot_along(
	walker: Node3D,
	coord: Vector2i,
	v: CastleVault,
	path: String,
	reach: float,
	up: float
) -> void:
	var r := v.rect
	var long_x := r.size.x >= r.size.y
	var run := r.size.x if long_x else r.size.y
	## Cut back in a closet: below five columns apart the two ends collapse onto each other and
	## the camera ends up aimed at the floor by its own feet.
	var inset := clampi((run - 5) / 2, 0, INSET)
	var mid := _rect_centre(r)
	var a := (
		Vector2i(r.position.x + inset, mid.y)
		if long_x
		else Vector2i(mid.x, r.position.y + inset)
	)
	var b := (
		Vector2i(r.end.x - 1 - inset, mid.y)
		if long_x
		else Vector2i(mid.x, r.end.y - 1 - inset)
	)
	print("  %s from %s to %s" % [v.describe(), a, b])
	await _shoot_lit(
		walker,
		_stand(coord, a, v.floor_y),
		_at(coord, b, v.floor_y) + Vector3(0.0, float(v.air_h) * VOX * up, 0.0),
		path,
		reach
	)


## From the foot of a flight, level on a middle tread. Same framing as the keep's stairwell
## shot: from the top the frame is all well lip, from below it is all slab soffit.
func _shoot_flight(
	walker: Node3D, coord: Vector2i, st: CastleStair, path: String
) -> void:
	var climb := Vector3(float(st.dir.x), 0.0, float(st.dir.y))
	var side := Vector3(float(st.across.x), 0.0, float(st.across.y))
	var mid := st.rise / 2
	await _shoot_lit(
		walker,
		_stand(coord, st.center_column(0), st.y_from) - climb * 1.2 + side * 0.6,
		_at(coord, st.center_column(mid), st.surface_at(mid) + 1),
		path,
		26.0
	)


## The chamber that best answers `want`. Null only for "tall", which a seed is allowed not to
## have; the others are guaranteed by the plan, so their absence is a failure worth hearing.
func _pick_vault(layout: CastleLayout, want: String) -> CastleVault:
	var best: CastleVault = null
	var score := 0
	for v: CastleVault in layout.dungeon_vaults:
		var s := 0
		match want:
			"wide":
				s = v.rect.size.x * v.rect.size.y if v.is_wide() and not v.is_tall() else 0
			"small":
				## Smallest by area, not narrowest: the narrowest chamber is usually also a
				## long one, and that is the corridor shot below.
				s = 10000 - v.rect.size.x * v.rect.size.y if v.is_small() else 0
			"tall":
				s = v.span_levels * v.rect.size.x * v.rect.size.y if v.is_tall() else 0
			"long":
				s = 100 * maxi(v.rect.size.x, v.rect.size.y) / v.narrow_span()
			_:
				push_error("unknown vault wanted: %s" % want)
		if s > score:
			score = s
			best = v
	if best == null and want != "tall":
		push_error("FAIL the dungeon has no %s chamber to photograph" % want)
	return best


## End of `r`'s long axis furthest from `from`, centred across — a corner would put the camera
## against two walls at once.
func _far_end(r: Rect2i, from: Vector2i) -> Vector2i:
	var mid := _rect_centre(r)
	var lo := (
		Vector2i(r.position.x, mid.y) if r.size.x >= r.size.y else Vector2i(mid.x, r.position.y)
	)
	var hi := (
		Vector2i(r.end.x - 1, mid.y) if r.size.x >= r.size.y else Vector2i(mid.x, r.end.y - 1)
	)
	return lo if Vector2(lo - from).length() > Vector2(hi - from).length() else hi


func _png(name: String) -> String:
	return "res://tools/castle_%s_s%d.png" % [name, _seed]


func _keep_flight(layout: CastleLayout) -> CastleStair:
	for st: CastleStair in layout.keep_stairs:
		if st.from_storey >= 0:
			return st
	push_error("FAIL the keep has no internal flight to photograph")
	return layout.crown_stair


## Widest room on a storey that is not the great hall.
func _plain_room(f: CastleFloor) -> Rect2i:
	var best := Rect2i()
	var area := 0
	for i in range(f.rooms.size()):
		if i == f.hall_index:
			continue
		var r: Rect2i = f.rooms[i]
		if r.size.x * r.size.y > area:
			area = r.size.x * r.size.y
			best = r
	assert(area > 0)
	return best


## Direction along the curtain from the crown landing, pointing at the longer run of wall.
func _crown_along(layout: CastleLayout) -> Vector3:
	var w := layout.wall_rect
	var walk := layout.crown_walk
	var dx := mini(walk.x - w.position.x, w.end.x - 1 - walk.x)
	var dy := mini(walk.y - w.position.y, w.end.y - 1 - walk.y)
	if dx < dy:
		## Landing sits on an east or west run, so the walk goes north/south.
		var north := walk.y - w.position.y
		var south := w.end.y - 1 - walk.y
		return Vector3(0.0, 0.0, -1.0 if north > south else 1.0)
	var west := walk.x - w.position.x
	var east := w.end.x - 1 - walk.x
	return Vector3(-1.0 if west > east else 1.0, 0.0, 0.0)


## A full day is 420 s and this tool takes five minutes of settles, so left running the
## outdoor half of the set drifts into the dark and photographs a black meadow. Stretching the
## day out past the run and then pinning the hour freezes the sun where every frame gets it.
func _stop_the_clock(city: CityRoot) -> void:
	var cycle := city.get_node_or_null("DayNightCycle")
	if cycle == null:
		push_error("FAIL no DayNightCycle to pin the sun with")
		return
	cycle.set("day_length_sec", 1_000_000.0)
	cycle.call("set_hour", SHOT_HOUR)
	print("sun pinned to %.1f h" % SHOT_HOUR)


## The HUD, the radar, the build slots and the error popup all sit in front of the camera. The
## popup is the one that matters: the project is missing a few outfit textures, so it opens over
## every frame and an interior shot is nothing but the popup.
func _hide_overlays(city: CityRoot) -> void:
	for child: Node in city.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
	var errors := get_node_or_null("/root/ErrorOverlay")
	assert(errors is CanvasLayer, "the ErrorOverlay autoload is what covers the frame")
	(errors as CanvasLayer).visible = false


func _hide_meshes(node: Node) -> void:
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).visible = false
		_hide_meshes(child)


func _corner_tower(layout: CastleLayout) -> CastleTower:
	for t: CastleTower in layout.towers:
		if t.kind == CastleTower.KIND_CORNER:
			return t
	push_error("FAIL the castle has no corner tower to photograph")
	return layout.towers[0]


func _rect_centre(r: Rect2i) -> Vector2i:
	return Vector2i(r.position.x + r.size.x / 2, r.position.y + r.size.y / 2)


## Eye of a body standing on the surface whose topmost solid voxel is `floor_y`.
func _stand(coord: Vector2i, column: Vector2i, floor_y: int) -> Vector3:
	return _at(coord, column, floor_y + 1) + Vector3(0.0, EYE, 0.0)


## District-local voxel column + Y → world metres, on the voxel centre.
func _at(coord: Vector2i, column: Vector2i, y: int) -> Vector3:
	var origin := DistrictCoord.origin_world(coord, VOX)
	return origin + Vector3(
		(float(column.x) + 0.5) * VOX, float(y) * VOX, (float(column.y) + 0.5) * VOX
	)


func _spawn_district(city: CityRoot) -> DistrictInstance:
	var want := city.spawn_district_coord
	var districts: Array = city._streamer.call("get_loaded_districts") as Array
	for entry: Variant in districts:
		var di: DistrictInstance = entry
		if di.coord == want and di.generator != null:
			return di
	return null


func _settle(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


## Terrain only meshes around the walker — park it at the eye before capturing.
func _shoot_near(walker: Node3D, eye: Vector3, target: Vector3, path: String) -> void:
	walker.global_position = eye
	await _settle(10.0)
	await _shoot(eye, target, path, 0.0)


## An interior frame, lit by a lamp at the camera. Enclosed keep rooms read as underground
## and go torch-lit, which is the accepted behaviour but leaves nothing to inspect.
func _shoot_lit(
	walker: Node3D,
	eye: Vector3,
	target: Vector3,
	path: String,
	reach: float,
	energy: float = 6.0
) -> void:
	walker.global_position = eye
	await _settle(10.0)
	await _shoot(eye, target, path, reach, energy)


func _shoot(
	eye: Vector3, target: Vector3, path: String, lamp_reach: float, lamp_energy: float = 6.0
) -> void:
	## Re-hidden per frame: the popup reopens on every new error, and streaming a fresh district
	## is exactly when the missing textures are asked for again.
	_hide_overlays(_city)
	var cam := Camera3D.new()
	cam.position = eye
	cam.fov = 70.0
	cam.far = 4000.0
	add_child(cam)
	cam.look_at(target, Vector3.UP)
	cam.make_current()
	## Doors open on proximity to *their* camera, and the one the district was streamed with
	## is the player's, which is nowhere near where this frame is taken from. Re-aim them, and
	## the settle below then gives the leaves time to finish swinging.
	if _doors != null:
		_doors.set_camera(cam)
	var lamp: OmniLight3D = null
	if lamp_reach > 0.0:
		lamp = OmniLight3D.new()
		lamp.position = eye
		lamp.omni_range = lamp_reach
		lamp.light_energy = lamp_energy
		lamp.shadow_enabled = false
		add_child(lamp)
	await _settle(3.0)
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("FAIL no viewport image for %s" % path)
	else:
		img.save_png(path)
		print("SAVED %s" % path)
	cam.queue_free()
	if lamp != null:
		lamp.queue_free()

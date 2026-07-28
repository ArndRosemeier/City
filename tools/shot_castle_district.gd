## Castle district look inspection: boots the live city into a Castle tile and saves the
## views the fortress has to survive — the whole thing from the air, the causeway seen from
## street level, the gatehouse, the bailey, a wall/tower elevation, and the Phase 2
## interiors: the keep from the bailey, the great hall, a stairwell, an ordinary room and
## the rampart from the crown landing.
##
## Run (-Command, not -File: the -File binder flattens a comma list into one argument):
##   powershell -Command "& '.\tools\run_test.ps1' -Scene shot_castle_district -Rendered
##     -GodotArgs @('--spawn-theme=castle','--city-seed=42')"
extends Node

const AERIAL_PNG := "res://tools/castle_aerial.png"
const APPROACH_PNG := "res://tools/castle_approach.png"
const GATEHOUSE_PNG := "res://tools/castle_gatehouse.png"
const COURTYARD_PNG := "res://tools/castle_courtyard.png"
const ELEVATION_PNG := "res://tools/castle_elevation.png"
const KEEP_PNG := "res://tools/castle_keep.png"
const HALL_PNG := "res://tools/castle_hall.png"
const STAIR_PNG := "res://tools/castle_stair.png"
const ROOM_PNG := "res://tools/castle_room.png"
const RAMPART_PNG := "res://tools/castle_rampart.png"

const VOX := 0.5
## Standing eye height, in metres above the walking surface.
const EYE := 1.7


func _ready() -> void:
	var city := CityRoot.new()
	city.city_seed = 42
	add_child(city)

	var deadline := Time.get_ticks_msec() + 120_000
	while city.get_node_or_null("Walker") == null:
		if Time.get_ticks_msec() > deadline:
			push_error("FAIL no walker after 120 s")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	var walker: Node3D = city.get_node_or_null("Walker")
	## The walker is only here to keep voxels meshed around the camera; inside a room its
	## own body is all the frame would contain.
	_hide_meshes(walker)

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
		AERIAL_PNG
	)

	## Standing on the meadow at the foot of the ramp, looking up the causeway at the gate.
	await _shoot_near(
		walker,
		foot + out * 16.0 + Vector3(0.0, deck + 1.7, 0.0),
		Vector3(gate_face.x, court + 6.0, gate_face.z),
		APPROACH_PNG
	)

	## Half way up the ramp — the gatehouse and its turrets at eye height.
	await _shoot_near(
		walker,
		foot.lerp(gate_face, 0.55) + Vector3(0.0, 5.0, 0.0),
		Vector3(gate_face.x, court + 5.0, gate_face.z),
		GATEHOUSE_PNG
	)

	## Inside the bailey, looking back at the gatehouse across the courtyard. Well clear of
	## the floor: the walker has to stand at the camera for the voxels here to mesh, and at
	## head height it is the only thing in frame.
	await _shoot_near(
		walker,
		bailey + Vector3(0.0, 8.0, 0.0),
		Vector3(gate_face.x, court + 8.0, gate_face.z),
		COURTYARD_PNG
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
		ELEVATION_PNG
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
		KEEP_PNG
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
		HALL_PNG,
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
		STAIR_PNG,
		30.0
	)

	## An ordinary room on an upper storey, corner to corner so the span shows.
	var top := layout.keep_floor(layout.keep_top_storey())
	var room := _plain_room(top)
	await _shoot_lit(
		walker,
		_stand(coord, room.position + Vector2i(3, 3), top.floor_y),
		_stand(coord, room.end - Vector2i(3, 3), top.floor_y),
		ROOM_PNG,
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
		RAMPART_PNG
	)

	print("RESULT: OK")
	get_tree().quit(0)


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
	walker: Node3D, eye: Vector3, target: Vector3, path: String, reach: float
) -> void:
	walker.global_position = eye
	await _settle(10.0)
	await _shoot(eye, target, path, reach)


func _shoot(eye: Vector3, target: Vector3, path: String, lamp_reach: float) -> void:
	var cam := Camera3D.new()
	cam.position = eye
	cam.fov = 70.0
	cam.far = 4000.0
	add_child(cam)
	cam.look_at(target, Vector3.UP)
	cam.make_current()
	var lamp: OmniLight3D = null
	if lamp_reach > 0.0:
		lamp = OmniLight3D.new()
		lamp.position = eye
		lamp.omni_range = lamp_reach
		lamp.light_energy = 6.0
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

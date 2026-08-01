## Monster Zoo look inspection: boots the live city into a Zoo tile and saves an
## aerial, a gate approach, and a battlefield view. Fails loudly if spawn is not Zoo.
##
## Camera poses come from ZooLayout (not a live voxel survey) — streamed chunks around
## the player are a fraction of the ring, so guessing the centre from loaded fence
## columns lands the camera in empty air.
##
## Run: powershell -Command "& '.\tools\run_test.ps1' -Scene shot_zoo_district -Rendered
##   -GodotArgs @('--spawn-theme=zoo','--city-seed=42')"
extends Node

const AERIAL_PNG := "res://tools/zoo_aerial.png"
const GATE_PNG := "res://tools/zoo_gate.png"
const FIELD_PNG := "res://tools/zoo_field.png"


func _ready() -> void:
	var city := CityRoot.new()
	city.city_seed = 42
	add_child(city)

	var deadline := Time.get_ticks_msec() + 180_000
	while city.get_node_or_null("Walker") == null:
		if Time.get_ticks_msec() > deadline:
			push_error("FAIL no walker after 180 s")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	var walker: Node3D = city.get_node_or_null("Walker")

	var theme := DistrictTheme.for_district(city.city_seed, city.spawn_district_coord)
	print("spawn district %s = %s" % [city.spawn_district_coord, theme.display_name])
	if theme.id != DistrictTheme.ZOO:
		push_error(
			"FAIL spawn district is %s, expected Monster Zoo — pass --spawn-theme=zoo"
			% theme.display_name
		)
		get_tree().quit(1)
		return

	## Cloak before stepping onto the field — the forever war does not wait for cameras.
	var ctrl := await _wait_zoo_controller(city, 60.0)
	if ctrl == null or ctrl.layout == null:
		push_error("FAIL no ZooController / layout under spawn district")
		get_tree().quit(1)
		return
	ctrl.request_cloak()
	print("spectator cloak granted for the look pass")

	var layout: ZooLayout = ctrl.layout
	var origin := ctrl.origin_vox
	var vs := ctrl.voxel_size
	var mid := _rect_world_center(layout.field_rect, layout.deck_y, origin, vs)
	var gate := _gate_world(layout, origin, vs)
	var field := _field_look_world(layout, origin, vs)
	var radius := (
		maxi(layout.field_rect.size.x, layout.field_rect.size.y) as float * vs * 0.5
	)
	print(
		"zoo layout: field=%s gate=%s mid=%s radius=%.1f m territories=%d"
		% [layout.field_rect, gate, mid, radius, layout.territory_count()]
	)

	## Let the spawn neighbourhood mesh before the gate shot.
	await _settle(10.0)

	## Gate first — that is where a player actually arrives with --spawn-theme=zoo.
	await _shoot_from(
		walker,
		gate,
		gate + Vector3(0.0, 3.4, 0.0),
		mid + Vector3(0.0, 8.0, 0.0),
		GATE_PNG
	)

	## Move onto the field so the aerial has streamed terrain under the camera.
	walker.global_position = mid + Vector3(0.0, 2.0, 0.0)
	await _settle(14.0)
	await _shoot_from(
		walker,
		mid,
		mid + Vector3(-radius * 0.2, radius * 1.35 + 40.0, radius * 0.55),
		mid,
		AERIAL_PNG
	)

	await _shoot_from(
		walker,
		field,
		field + Vector3(32.0, 16.0, 28.0),
		field + Vector3(-10.0, 3.0, -8.0),
		FIELD_PNG
	)

	print("RESULT: OK")
	get_tree().quit(0)


func _gate_world(layout: ZooLayout, origin: Vector3i, vs: float) -> Vector3:
	## Stand on the visitor side of the opening, just outside the ring.
	var g := layout.gate_rect
	var gmid := Vector2i(
		g.position.x + g.size.x / 2,
		g.position.y + g.size.y / 2
	)
	var stand := gmid - layout.gate_dir * 6
	return Vector3(
		(float(origin.x + stand.x) + 0.5) * vs,
		float(origin.y + layout.deck_y + 1) * vs + 0.2,
		(float(origin.z + stand.y) + 0.5) * vs
	)


func _field_look_world(layout: ZooLayout, origin: Vector3i, vs: float) -> Vector3:
	## A bit inside the plaza lip so ruined houses and turf plates are in frame.
	var p := layout.plaza_rect
	if p.size.x <= 0:
		return _rect_world_center(layout.field_rect, layout.deck_y, origin, vs)
	var inward := layout.gate_dir
	var stand := Vector2i(
		p.position.x + p.size.x / 2,
		p.position.y + p.size.y / 2
	) + inward * 18
	return Vector3(
		(float(origin.x + stand.x) + 0.5) * vs,
		float(origin.y + layout.deck_y + 1) * vs + 0.2,
		(float(origin.z + stand.y) + 0.5) * vs
	)


func _rect_world_center(r: Rect2i, deck_y: int, origin: Vector3i, vs: float) -> Vector3:
	return Vector3(
		(float(origin.x) + float(r.position.x) + float(r.size.x) * 0.5) * vs,
		float(origin.y + deck_y + 1) * vs,
		(float(origin.z) + float(r.position.y) + float(r.size.y) * 0.5) * vs
	)


func _wait_zoo_controller(city: CityRoot, sec: float) -> ZooController:
	var until := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < until:
		var found := _find_zoo_controller(city)
		if found != null:
			return found
		await get_tree().process_frame
	return null


func _find_zoo_controller(city: CityRoot) -> ZooController:
	var stack: Array[Node] = [city]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is ZooController:
			return n as ZooController
		for c in n.get_children():
			stack.append(c)
	return null


func _shoot_from(
	walker: Node3D, stand: Vector3, cam_pos: Vector3, look_at: Vector3, path: String
) -> void:
	walker.global_position = stand
	await _settle(2.5)
	var cam: Camera3D = walker.get_node_or_null("Camera3D") as Camera3D
	if cam == null:
		cam = get_viewport().get_camera_3d()
	if cam == null:
		push_error("FAIL no camera")
		return
	cam.global_position = cam_pos
	cam.look_at(look_at, Vector3.UP)
	await _settle(1.5)
	var img: Image = get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	if err != OK:
		push_error("FAIL save %s: %s" % [path, err])
	else:
		print("wrote %s" % path)


func _settle(sec: float) -> void:
	var until := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame

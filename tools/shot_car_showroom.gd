## Car look inspection: renders a lineup of the whole catalog plus per-profile hero,
## side and aerial shots, so the procedural kit can be judged without hunting for
## traffic in the live city.
##
## Run: Godot --path . res://tools/shot_car_showroom.tscn
extends Node

const OUT_DIR := "res://tools/carshots"
const LINEUP_PNG := "res://tools/car_lineup.png"
## One per distinct silhouette, plus the two liveries.
const HERO_IDS: Array[String] = ["sedan", "hatchback_sports", "suv", "van", "truck", "police"]
## Gap between cars in the lineup, in metres.
const LINEUP_PITCH := 5.8


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_build_stage()
	VehicleCatalog.reload()
	if not VehicleCatalog.is_ready():
		push_error("FAIL vehicle catalog not ready")
		get_tree().quit(1)
		return

	await _shoot_lineup()
	for id in HERO_IDS:
		await _shoot_hero(id)

	print("RESULT: OK")
	get_tree().quit(0)


func _shoot_lineup() -> void:
	var lineup := Node3D.new()
	lineup.name = "Lineup"
	add_child(lineup)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var count := VehicleCatalog.count()
	for i in range(count):
		var entry: Dictionary = VehicleCatalog.entry_at(i)
		var car := ProceduralVehicle.build(entry, rng)
		if car == null:
			push_error("FAIL procedural build returned null for %s" % str(entry.get("id", "?")))
			get_tree().quit(1)
			return
		## Two staggered rows: a single row of ten is unreadable at framing distance.
		var col := i % 5
		var row := i / 5
		car.position = Vector3(
			(float(col) - 2.0) * LINEUP_PITCH, 0.0, float(row) * 7.5 - 3.75
		)
		car.rotation.y = deg_to_rad(26.0)
		lineup.add_child(car)
	await _settle(0.5)
	await _shoot(Vector3(0.0, 12.5, 20.0), Vector3(0.0, 0.6, 0.0), LINEUP_PNG)
	lineup.queue_free()
	await _settle(0.3)


func _shoot_hero(id: String) -> void:
	var entry: Dictionary = VehicleCatalog.entry_by_id(id)
	if entry.is_empty():
		push_error("FAIL no catalog entry '%s'" % id)
		get_tree().quit(1)
		return
	var visual := VehicleVisual.new()
	visual.name = "Hero_%s" % id
	add_child(visual)
	visual.setup(entry, 3, 7)
	await _settle(0.5)
	if not visual.ready_visual:
		push_error("FAIL hero visual not ready for %s" % id)
		get_tree().quit(1)
		return
	var ext := visual.body_half_extents()
	print(
		"%-18s body %.2f x %.2f x %.2f m  glass %d"
		% [id, ext.x * 2.0, ext.y * 2.0, ext.z * 2.0, visual.glass_material_count]
	)

	var focus := Vector3(0.0, ext.y * 0.55, 0.0)
	var reach := ext.z * 2.0
	await _shoot(
		Vector3(reach * 0.62, ext.y * 1.5, -reach * 0.90), focus, "%s/%s_front.png" % [OUT_DIR, id]
	)
	await _shoot(Vector3(reach * 1.35, ext.y * 0.9, 0.0), focus, "%s/%s_side.png" % [OUT_DIR, id])
	## Roughly the game camera's downward angle, and the view that shows whether the car
	## casts a shadow or floats on the road.
	await _shoot(
		Vector3(reach * 0.70, reach * 0.78, reach * 0.80), focus, "%s/%s_aerial.png" % [OUT_DIR, id]
	)
	## Front wheel close-up: the arch opening has to swallow the tyre, not sit behind it.
	await _shoot(
		Vector3(2.1, 0.75, -1.4), Vector3(0.6, 0.34, -1.35), "%s/%s_wheel.png" % [OUT_DIR, id]
	)
	visual.queue_free()
	await _settle(0.25)


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.42, 0.55, 0.72)
	sky_mat.sky_horizon_color = Color(0.72, 0.76, 0.80)
	sky_mat.ground_bottom_color = Color(0.24, 0.24, 0.26)
	sky_mat.ground_horizon_color = Color(0.45, 0.45, 0.47)
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)

	## Asphalt-toned pad: a car reads very differently over road grey than over a void.
	var pad := MeshInstance3D.new()
	pad.name = "Pad"
	var plane := PlaneMesh.new()
	plane.size = Vector2(160.0, 160.0)
	pad.mesh = plane
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.30, 0.31, 0.33)
	pad_mat.roughness = 0.9
	pad.material_override = pad_mat
	add_child(pad)


func _settle(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _shoot(eye: Vector3, target: Vector3, path: String) -> void:
	var cam := Camera3D.new()
	cam.position = eye
	cam.fov = 45.0
	cam.far = 500.0
	add_child(cam)
	cam.look_at(target, Vector3.UP)
	cam.make_current()
	await _settle(0.35)
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("FAIL no viewport image for %s" % path)
	else:
		img.save_png(path)
	cam.queue_free()

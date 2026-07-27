## Pedestrian outfit look inspection: renders every catalog outfit as a lineup plus a
## close-up pair, so texture import changes (compression, size limits) can be judged.
##
## Run: Godot --path . res://tools/shot_ped_outfits.tscn
extends Node

const OUT_DIR := "res://tools/pedshots"
const LINEUP_PNG := "res://tools/ped_lineup.png"
## Gap between peds in the lineup, in metres.
const LINEUP_PITCH := 0.85


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_build_stage()
	PedOutfitCatalog.reload()
	if PedOutfitCatalog.count() <= 0:
		push_error("FAIL ped outfit catalog empty")
		get_tree().quit(1)
		return

	var outfits := PedOutfitCatalog.all_outfits()
	await _shoot_lineup(outfits)
	for outfit in outfits:
		await _shoot_closeup(outfit)

	print("RESULT: OK")
	get_tree().quit(0)


func _spawn_visual(outfit: PedOutfit, parent: Node) -> CrowdPedVisual:
	var visual := CrowdPedVisual.new()
	visual.name = "Ped_%s" % outfit.variant_id
	parent.add_child(visual)
	visual.bind_agent(0, outfit.female, 1.0, outfit)
	return visual


func _shoot_lineup(outfits: Array[PedOutfit]) -> void:
	var lineup := Node3D.new()
	lineup.name = "Lineup"
	add_child(lineup)
	var half := float(outfits.size() - 1) * 0.5
	for i in outfits.size():
		var visual := _spawn_visual(outfits[i], lineup)
		visual.position = Vector3((float(i) - half) * LINEUP_PITCH, 0.0, 0.0)
	await _settle(0.6)
	## Bodies face -Z (CrowdPedVisual rotates them), so shoot from -Z to see faces.
	await _shoot(Vector3(0.0, 1.6, -6.4), Vector3(0.0, 0.9, 0.0), LINEUP_PNG)
	lineup.queue_free()
	await _settle(0.3)


## Head and torso at the closest distance a player ever sees a ped from.
func _shoot_closeup(outfit: PedOutfit) -> void:
	var visual := _spawn_visual(outfit, self)
	await _settle(0.4)
	await _shoot(
		Vector3(0.0, 1.55, -1.1),
		Vector3(0.0, 1.5, 0.0),
		"%s/%s_head.png" % [OUT_DIR, outfit.variant_id]
	)
	await _shoot(
		Vector3(0.0, 1.0, -2.1),
		Vector3(0.0, 0.95, 0.0),
		"%s/%s_body.png" % [OUT_DIR, outfit.variant_id]
	)
	visual.queue_free()
	await _settle(0.2)


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
	sun.rotation_degrees = Vector3(-38.0, 25.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)

	var pad := MeshInstance3D.new()
	pad.name = "Pad"
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	pad.mesh = plane
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.32, 0.33, 0.35)
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

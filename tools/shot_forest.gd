## ForestComposer close-ups — 30×30 m so floor rocks read clearly.
##
##   powershell -File tools\run_test.ps1 shot_forest -Rendered -TimeoutSec 240
extends Node

const ForestComposerScript := preload("res://scripts/city/forest_composer.gd")
const OUT_DIR := "res://tools/"
const VOX := 0.5
const DECK_Y := 2
## 30 m × 30 m — close enough to see single-voxel rocks.
const AREA_M := 30.0
const AREA_VOX := int(AREA_M / VOX)
const ORIGIN := Vector3i(8, DECK_Y, 8)

const PRESETS: Array[Dictionary] = [
	{
		"name": "floor_sparse",
		"density": 0.22,
		"min_height_m": 12.0,
		"max_height_m": 16.0,
		"seed": 11,
	},
	{
		"name": "floor_dense",
		"density": 0.55,
		"min_height_m": 10.0,
		"max_height_m": 14.0,
		"seed": 29,
	},
]


func _ready() -> void:
	var root := Node3D.new()
	add_child(root)
	_build_environment(root)
	for preset: Dictionary in PRESETS:
		await _shoot_preset(root, preset)
	print("RESULT: OK")
	get_tree().quit(0)


func _shoot_preset(root: Node3D, preset: Dictionary) -> void:
	var name: String = preset["name"]
	var density := float(preset["density"])
	var h0 := float(preset["min_height_m"])
	var h1 := float(preset["max_height_m"])
	var seed_i := int(preset["seed"])
	print(
		"FOREST_SHOT %s density=%.2f height=%.0f..%.0fm area=%dx%d m"
		% [name, density, h0, h1, int(AREA_M), int(AREA_M)]
	)

	for child in root.get_children():
		if child is VoxelTerrain or child is VoxelViewer or child is Camera3D:
			child.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	var terrain := VoxelTerrain.new()
	terrain.scale = Vector3(VOX, VOX, VOX)
	var mesher := VoxelMesherBlocky.new()
	mesher.library = VoxelBlockLibrary.build()
	terrain.mesher = mesher
	const AirGeneratorScript := preload("res://scripts/city/air_generator.gd")
	terrain.generator = AirGeneratorScript.new()
	var pad := 16
	terrain.bounds = AABB(
		Vector3(-pad, 0, -pad),
		Vector3(AREA_VOX + pad * 2, 72, AREA_VOX + pad * 2)
	)
	terrain.max_view_distance = 160
	terrain.generate_collisions = false
	root.add_child(terrain)

	var viewer := VoxelViewer.new()
	viewer.view_distance = 160
	viewer.requires_visuals = true
	root.add_child(viewer)

	var tool := terrain.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	var edit_min := Vector3(ORIGIN.x, 0, ORIGIN.z)
	var edit_size := Vector3(AREA_VOX, 48, AREA_VOX)
	var guard := 0
	while not tool.is_area_editable(AABB(edit_min, edit_size)) and guard < 400:
		guard += 1
		viewer.global_position = Vector3(
			(float(ORIGIN.x) + float(AREA_VOX) * 0.5) * VOX,
			12.0,
			(float(ORIGIN.z) + float(AREA_VOX) * 0.5) * VOX
		)
		await get_tree().process_frame

	var brush := CityBrush.new(tool)
	var forest := ForestComposerScript.new()
	forest.brush = brush
	forest.rng = RandomNumberGenerator.new()
	forest.rng.seed = seed_i
	forest.ground_y = DECK_Y
	forest.density = density
	forest.min_height_m = h0
	forest.max_height_m = h1

	var min_v := ORIGIN
	var max_v := ORIGIN + Vector3i(AREA_VOX, 1, AREA_VOX)
	brush.begin_edit()
	forest.compose(min_v, max_v)
	brush.end_edit()

	var cx := (float(ORIGIN.x) + float(AREA_VOX) * 0.5) * VOX
	var cz := (float(ORIGIN.z) + float(AREA_VOX) * 0.5) * VOX
	var deck_m := float(DECK_Y) * VOX
	await get_tree().create_timer(2.5).timeout

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	## Low three-quarter — rocks on the lawn in the foreground, trunks behind.
	cam.global_position = Vector3(cx - 6.0, deck_m + 3.2, cz - 11.0)
	cam.look_at(Vector3(cx + 2.0, deck_m + 1.2, cz + 2.0))
	viewer.global_position = cam.global_position
	await get_tree().create_timer(1.5).timeout

	var out_path := OUT_DIR + "forest_%s.png" % name
	get_viewport().get_texture().get_image().save_png(out_path)
	print("FOREST_SHOT wrote %s" % out_path)
	cam.queue_free()


func _build_environment(root: Node3D) -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.62, 0.74, 0.86)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.74, 0.78)
	environment.ambient_light_energy = 0.9
	env.environment = environment
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 35, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	root.add_child(sun)

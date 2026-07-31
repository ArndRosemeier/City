## Arena district look inspection: boots the live city into an Arena tile and saves an
## aerial, a gate approach, and a pit-floor view.
##
## Run: powershell -Command "& '.\tools\run_test.ps1' -Scene shot_arena_district -Rendered
##   -GodotArgs @('--spawn-theme=arena','--city-seed=42')"
extends Node

const AERIAL_PNG := "res://tools/arena_aerial.png"
const GATE_PNG := "res://tools/arena_gate.png"
const PIT_PNG := "res://tools/arena_pit.png"
const DECK_Y := 6


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
	if theme.id != DistrictTheme.ARENA:
		push_error("FAIL spawn district is %s, expected Arena" % theme.display_name)
		get_tree().quit(1)
		return

	await _settle(12.0)
	var center := DistrictCoord.center_world(city.spawn_district_coord, CityRoot.VOXEL_SIZE)
	center.y = 0.0
	walker.global_position = Vector3(center.x, 14.0, center.z)
	await _settle(16.0)

	var survey := _survey_shell(city, center)
	if int(survey["columns"]) == 0:
		push_error("FAIL no ARENA_SHELL in the spawn tile")
		get_tree().quit(1)
		return
	var mid: Vector3 = survey["center"]
	var radius: float = survey["radius"]
	print(
		"arena: %d shell columns, centre %s, half-width %.1f m"
		% [int(survey["columns"]), mid, radius]
	)

	await _shoot_from(
		walker,
		mid,
		mid + Vector3(-radius * 0.75, radius * 0.85 + 40.0, radius * 0.95),
		mid,
		AERIAL_PNG
	)

	var gate: Vector3 = survey["gate"]
	await _shoot_from(
		walker,
		gate,
		gate + Vector3(0.0, 2.4, 0.0),
		mid + Vector3(0.0, 3.0, 0.0),
		GATE_PNG
	)

	var pit: Vector3 = survey["pit"]
	await _shoot_from(
		walker,
		pit,
		pit + Vector3(18.0, 8.0, 18.0),
		pit + Vector3(0.0, 1.0, 0.0),
		PIT_PNG
	)

	print("RESULT: OK")
	get_tree().quit(0)


func _survey_shell(city: CityRoot, center: Vector3) -> Dictionary:
	var terrain: Node = city.get_node_or_null("VoxelTerrain")
	if terrain == null:
		push_error("FAIL no VoxelTerrain node on CityRoot")
		return {"columns": 0}
	var tool_: Object = terrain.call("get_voxel_tool")
	var cx := int(center.x / CityRoot.VOXEL_SIZE)
	var cz := int(center.z / CityRoot.VOXEL_SIZE)
	var hx := DistrictCoord.SIZE_X_VOX / 2 - 4
	var hz := DistrictCoord.SIZE_Z_VOX / 2 - 4
	var columns := 0
	var sum_x := 0
	var sum_z := 0
	var min_x := 999999
	var max_x := -999999
	var gate := Vector3.ZERO
	var pit := Vector3.ZERO
	for dz in range(-hz, hz + 1, 4):
		for dx in range(-hx, hx + 1, 4):
			var x := cx + dx
			var z := cz + dz
			var id := int(tool_.call("get_voxel", Vector3i(x, DECK_Y + 3, z)))
			if id != VoxelMaterial.ARENA_SHELL:
				## Sand / gravel pad inside the pit.
				var floor_id := int(tool_.call("get_voxel", Vector3i(x, DECK_Y, z)))
				if floor_id == VoxelMaterial.DIRT and pit == Vector3.ZERO:
					pit = Vector3(
						(float(x) + 0.5) * CityRoot.VOXEL_SIZE,
						float(DECK_Y + 1) * CityRoot.VOXEL_SIZE,
						(float(z) + 0.5) * CityRoot.VOXEL_SIZE
					)
				continue
			columns += 1
			sum_x += x
			sum_z += z
			min_x = mini(min_x, x)
			max_x = maxi(max_x, x)
			if gate == Vector3.ZERO:
				var gravel := int(tool_.call("get_voxel", Vector3i(x, DECK_Y, z)))
				if gravel == VoxelMaterial.GRAVEL:
					gate = Vector3(
						(float(x) + 0.5) * CityRoot.VOXEL_SIZE,
						float(DECK_Y + 1) * CityRoot.VOXEL_SIZE + 0.2,
						(float(z) + 0.5) * CityRoot.VOXEL_SIZE
					)
	if columns == 0:
		return {"columns": 0}
	var mid := Vector3(
		(float(sum_x) / float(columns) + 0.5) * CityRoot.VOXEL_SIZE,
		float(DECK_Y + 1) * CityRoot.VOXEL_SIZE,
		(float(sum_z) / float(columns) + 0.5) * CityRoot.VOXEL_SIZE
	)
	var radius := maxf(float(max_x - min_x) * CityRoot.VOXEL_SIZE * 0.5, 40.0)
	if gate == Vector3.ZERO:
		gate = mid + Vector3(0.0, 0.0, radius * 0.9)
	if pit == Vector3.ZERO:
		pit = mid
	return {
		"columns": columns,
		"center": mid,
		"radius": radius,
		"gate": gate,
		"pit": pit,
	}


func _shoot_from(
	walker: Node3D, stand: Vector3, cam_pos: Vector3, look_at: Vector3, path: String
) -> void:
	walker.global_position = stand
	await _settle(2.0)
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

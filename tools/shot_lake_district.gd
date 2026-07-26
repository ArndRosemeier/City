## Lake district look inspection: boots the live city into a Lake tile and saves an
## aerial, a shore-level and an island shot so the basin can be judged visually.
##
## Run: Godot --path . res://tools/shot_lake_district.tscn -- --spawn-theme=lake --city-seed=42
extends Node

const AERIAL_PNG := "res://tools/lake_aerial.png"
const SHORE_PNG := "res://tools/lake_shore.png"
const ISLAND_PNG := "res://tools/lake_island.png"
## Street deck sits at this voxel row in every district.
const DECK_Y := 6


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

	var theme := DistrictTheme.for_district(city.city_seed, city.spawn_district_coord)
	print("spawn district %s = %s" % [city.spawn_district_coord, theme.display_name])
	if theme.id != DistrictTheme.LAKE:
		push_error("FAIL spawn district is %s, expected Lake" % theme.display_name)
		get_tree().quit(1)
		return

	await _settle(10.0)
	var center := DistrictCoord.center_world(city.spawn_district_coord, CityRoot.VOXEL_SIZE)
	center.y = 0.0
	walker.global_position = Vector3(center.x, 12.0, center.z)
	await _settle(14.0)

	var survey := _survey_water(city, center)
	if int(survey["columns"]) == 0:
		push_error("FAIL no water voxels in the spawn tile")
		get_tree().quit(1)
		return
	var mid: Vector3 = survey["center"]
	var radius: float = survey["radius"]
	print(
		"lake: %d surface columns, centre %s, half-width %.1f m, islands sampled %d"
		% [int(survey["columns"]), mid, radius, int(survey["island_columns"])]
	)

	## Oblique aerial. The walker has to stay in the middle of the basin: terrain only
	## meshes around it, and following the camera out unloads the whole tile.
	await _shoot_from(
		walker,
		mid,
		mid + Vector3(-radius * 0.8, radius * 1.0 + 30.0, radius * 1.05),
		mid,
		AERIAL_PNG
	)
	## Standing on the beach looking across — this is where a stitched water surface
	## or a hard shore cut would show up.
	var shore: Vector3 = survey["shore"]
	await _shoot_from(
		walker, shore, shore + Vector3(0.0, 2.2, 0.0), mid + Vector3(0.0, 1.0, 0.0), SHORE_PNG
	)

	var island: Vector3 = survey["island"]
	if island != Vector3.ZERO:
		await _shoot_from(
			walker,
			island,
			island + Vector3(26.0, 9.0, 26.0),
			island + Vector3(0.0, 1.0, 0.0),
			ISLAND_PNG
		)
	else:
		push_error("FAIL no island found in the basin")
		get_tree().quit(1)
		return

	print("RESULT: OK")
	get_tree().quit(0)


## Probes the live volume at deck level: water extent, a beach stance, and an island.
func _survey_water(city: CityRoot, center: Vector3) -> Dictionary:
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
	var min_x := cx + hx
	var max_x := cx - hx
	var min_z := cz + hz
	var max_z := cz - hz
	var islands := 0
	var island := Vector3i.ZERO
	var z := cz - hz
	while z < cz + hz:
		var x := cx - hx
		while x < cx + hx:
			if int(tool_.call("get_voxel", Vector3i(x, DECK_Y, z))) == VoxelMaterial.WATER:
				columns += 1
				sum_x += x
				sum_z += z
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_z = mini(min_z, z)
				max_z = maxi(max_z, z)
			elif int(tool_.call("get_voxel", Vector3i(x, DECK_Y + 2, z))) == VoxelMaterial.PARK:
				## Grass two voxels above the deck can only be an island crown.
				islands += 1
				if island == Vector3i.ZERO:
					island = Vector3i(x, DECK_Y + 2, z)
			x += 2
		z += 2
	if columns == 0:
		return {"columns": 0}
	var mid_x := sum_x / columns
	var mid_z := sum_z / columns
	var radius := float(maxi(max_x - min_x, max_z - min_z)) * 0.5 * CityRoot.VOXEL_SIZE
	## Walk west from the centre until the water ends — that column is the beach.
	var shore_x := mid_x
	while shore_x > cx - hx:
		if int(tool_.call("get_voxel", Vector3i(shore_x, DECK_Y, mid_z))) != VoxelMaterial.WATER:
			break
		shore_x -= 1
	return {
		"columns": columns,
		"island_columns": islands,
		"center": Vector3(float(mid_x), float(DECK_Y + 1), float(mid_z)) * CityRoot.VOXEL_SIZE,
		"radius": radius,
		"shore": Vector3(float(shore_x - 3), float(DECK_Y + 1), float(mid_z)) * CityRoot.VOXEL_SIZE,
		"island": (
			Vector3.ZERO if island == Vector3i.ZERO
			else Vector3(island) * CityRoot.VOXEL_SIZE
		),
	}


func _settle(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


## Terrain only meshes around the walker, so it is the anchor — the camera is free.
func _shoot_from(
	walker: Node3D, anchor: Vector3, eye: Vector3, target: Vector3, path: String
) -> void:
	walker.global_position = anchor + Vector3(0.0, 2.0, 0.0)
	await _settle(9.0)
	await _shoot(eye, target, path)


func _shoot(eye: Vector3, target: Vector3, path: String) -> void:
	var cam := Camera3D.new()
	cam.position = eye
	cam.fov = 70.0
	cam.far = 4000.0
	add_child(cam)
	cam.look_at(target, Vector3.UP)
	cam.make_current()
	await _settle(3.0)
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("FAIL no viewport image for %s" % path)
	else:
		img.save_png(path)
		print("SAVED %s" % path)
	cam.queue_free()

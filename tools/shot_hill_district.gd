## Hill district look inspection: boots the live city into a Hill tile and saves an
## aerial, a road-level and an eye-level shot so the terrain can be judged visually.
##
## Run: Godot --path . res://tools/shot_hill_district.tscn -- --spawn-theme=hill --city-seed=42
extends Node

const AERIAL_PNG := "res://tools/hill_aerial.png"
const ROAD_PNG := "res://tools/hill_road.png"
const EYE_PNG := "res://tools/hill_eye.png"
const CAVE_PNG := "res://tools/hill_cave.png"
const HALL_PNG := "res://tools/hill_cave_hall.png"
const SHAFT_PNG := "res://tools/hill_cave_shaft.png"
const SLOPE_PNG := "res://tools/hill_slope.png"
## Street deck sits at this voxel row in every district.
const DECK_Y := 6
const ROCK_IDS: Array[int] = [
	VoxelMaterial.BEDROCK,
	VoxelMaterial.STONE,
	VoxelMaterial.BRICK,
	VoxelMaterial.DIRT,
	VoxelMaterial.GRAVEL,
	VoxelMaterial.CAVE_WALL,
	VoxelMaterial.CAVE_FLOOR,
]


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
	if theme.id != DistrictTheme.HILL:
		push_error("FAIL spawn district is %s, expected Hill" % theme.display_name)
		get_tree().quit(1)
		return

	await _settle(10.0)
	var inst := _spawn_district(city)
	if inst == null:
		push_error("FAIL spawn district instance not loaded")
		get_tree().quit(1)
		return
	var planner := inst.generator.get_planner()
	print("hill rect %s, road cells %d" % [planner.large_hill, _road_cells(planner)])

	var center := _district_center(city.spawn_district_coord)
	## Peak sits near the tile centre; park the walker there so LOD keeps it meshed.
	walker.global_position = Vector3(center.x, 40.0, center.z)
	await _settle(14.0)

	## Oblique aerial so the single massif reads as a dome, not a flat mottled square.
	await _shoot_near(
		walker,
		center + Vector3(-160.0, 110.0, 200.0),
		center + Vector3(0.0, 22.0, 0.0),
		AERIAL_PNG
	)
	## South-edge connector looking north into the massif (row 19 is the seam avenue).
	var south_edge := center + Vector3(0.0, 8.0, float(DistrictCoord.SIZE_Z_VOX) * 0.48 * CityRoot.VOXEL_SIZE)
	await _shoot_near(walker, south_edge, center + Vector3(0.0, 30.0, 0.0), ROAD_PNG)
	await _shoot_near(
		walker,
		center + Vector3(-50.0, 16.0, 60.0),
		center + Vector3(0.0, 30.0, -20.0),
		EYE_PNG
	)

	_report_surface(city)
	await _shoot_slope(city, walker)

	var mouth := _find_cave_mouth(city)
	if mouth.is_empty():
		push_error("FAIL no cave mouth reachable from the open air")
		get_tree().quit(1)
		return
	var inside: Vector3 = mouth["inside"]
	var outside: Vector3 = mouth["outside"]
	print("cave mouth at %s, approach from %s" % [inside, outside])
	## Terrain only meshes around the walker, so bring it along before shooting.
	walker.global_position = outside + Vector3(0.0, 4.0, 0.0)
	await _settle(12.0)
	await _shoot(outside, inside, CAVE_PNG)

	await _shoot_interior(city, walker)

	print("RESULT: OK")
	get_tree().quit(0)


## The massif is meant to be hollow in three dimensions, so sample its air profile and
## shoot the two views that expose it: a hall at eye level and a shaft looking up.
func _shoot_interior(city: CityRoot, walker: Node3D) -> void:
	var terrain: Node = city.get_node_or_null("VoxelTerrain")
	var tool_: Object = terrain.call("get_voxel_tool")
	var center := DistrictCoord.center_world(city.spawn_district_coord, CityRoot.VOXEL_SIZE)
	var cx := int(center.x / CityRoot.VOXEL_SIZE)
	var cz := int(center.z / CityRoot.VOXEL_SIZE)
	var runs_total := 0
	var columns := 0
	var best_hall := Vector3i.ZERO
	var best_hall_run := 0
	var best_stack := Vector3i.ZERO
	var best_stack_runs := 0
	var z := cz - 100
	while z < cz + 100:
		var x := cx - 100
		while x < cx + 100:
			var runs := 0
			var run := 0
			var run_top := DECK_Y
			var solid_above := false
			for y in range(DECK_Y + 75, DECK_Y, -1):
				var id := int(tool_.call("get_voxel", Vector3i(x, y, z)))
				if id != VoxelMaterial.AIR:
					solid_above = solid_above or id in ROCK_IDS
					if run > 0:
						runs += 1
						if run > best_hall_run:
							best_hall_run = run
							best_hall = Vector3i(x, run_top - run / 2, z)
					run = 0
					continue
				if not solid_above:
					continue
				if run == 0:
					run_top = y
				run += 1
			if run > 0:
				runs += 1
			if runs > 0:
				columns += 1
				runs_total += runs
			if runs > best_stack_runs:
				best_stack_runs = runs
				best_stack = Vector3i(x, DECK_Y + 3, z)
			x += 2
		z += 2
	if columns == 0:
		push_error("FAIL no hollow columns inside the massif")
		return
	print(
		"cave profile: hollow columns=%d avg air runs/column=%.2f tallest hall=%d vox"
		% [columns, float(runs_total) / float(columns), best_hall_run]
	)
	if best_hall_run > 0:
		var hall := Vector3(best_hall) * CityRoot.VOXEL_SIZE
		walker.global_position = hall
		await _settle(12.0)
		await _shoot(hall + Vector3(0.0, 1.0, 0.0), hall + Vector3(24.0, 0.0, 10.0), HALL_PNG)
	if best_stack_runs > 1:
		var foot := Vector3(best_stack) * CityRoot.VOXEL_SIZE
		walker.global_position = foot
		await _settle(12.0)
		## Above the walker's crown — otherwise the character model fills an upward shot.
		await _shoot(foot + Vector3(0.0, 3.5, 0.0), foot + Vector3(3.0, 24.0, 3.0), SHAFT_PNG)


## Close enough to count voxels and name the material on every face.
func _shoot_slope(city: CityRoot, walker: Node3D) -> void:
	var terrain: Node = city.get_node_or_null("VoxelTerrain")
	var tool_: Object = terrain.call("get_voxel_tool")
	var center := DistrictCoord.center_world(city.spawn_district_coord, CityRoot.VOXEL_SIZE)
	var cx := int(center.x / CityRoot.VOXEL_SIZE)
	var cz := int(center.z / CityRoot.VOXEL_SIZE)
	## Stay near the tile centre: terrain only meshes around the walker.
	for radius: int in [40, 80, 120]:
		var z := cz - radius
		while z < cz + radius:
			var x: int = cx - radius
			while x < cx + radius:
				var here := _surface_y(tool_, x, z)
				if here > DECK_Y + 14 and _surface_y(tool_, x + 20, z) < here - 8:
					var target := Vector3(float(x), float(here), float(z)) * CityRoot.VOXEL_SIZE
					print("slope close-up at voxel (%d, %d, %d)" % [x, here, z])
					walker.global_position = target + Vector3(14.0, 6.0, 0.0)
					await _settle(10.0)
					await _shoot(target + Vector3(12.0, 2.0, 2.0), target, SLOPE_PNG)
					return
				x += 4
			z += 4
	push_error("FAIL no slope steep enough for a close-up")


## What the player actually sees: topmost solid voxel of every raised column.
func _report_surface(city: CityRoot) -> void:
	var terrain: Node = city.get_node_or_null("VoxelTerrain")
	var tool_: Object = terrain.call("get_voxel_tool")
	var center := DistrictCoord.center_world(city.spawn_district_coord, CityRoot.VOXEL_SIZE)
	var cx := int(center.x / CityRoot.VOXEL_SIZE)
	var cz := int(center.z / CityRoot.VOXEL_SIZE)
	var counts: Dictionary = {}
	var sides: Dictionary = {}
	var side_total := 0
	var raised := 0
	var z := cz - DistrictCoord.SIZE_Z_VOX / 2 + 4
	while z < cz + DistrictCoord.SIZE_Z_VOX / 2 - 4:
		var x := cx - DistrictCoord.SIZE_X_VOX / 2 + 4
		while x < cx + DistrictCoord.SIZE_X_VOX / 2 - 4:
			var top := _surface_y(tool_, x, z)
			if top > DECK_Y + 3:
				raised += 1
				var id := int(tool_.call("get_voxel", Vector3i(x, top, z)))
				counts[id] = int(counts.get(id, 0)) + 1
				## Vertical faces dominate a hillside seen from below, so tally those too.
				var down := _surface_y(tool_, x + 1, z)
				for y in range(down + 1, top + 1):
					var sid := int(tool_.call("get_voxel", Vector3i(x, y, z)))
					sides[sid] = int(sides.get(sid, 0)) + 1
					side_total += 1
			x += 3
		z += 3
	print("raised surface samples: %d" % raised)
	for id: Variant in counts.keys():
		print("  top  mat %2d: %5d (%2d%%)" % [id, counts[id], int(counts[id]) * 100 / maxi(1, raised)])
	for id2: Variant in sides.keys():
		print(
			"  side mat %2d: %5d (%2d%%)"
			% [id2, sides[id2], int(sides[id2]) * 100 / maxi(1, side_total)]
		)


func _surface_y(tool_: Object, x: int, z: int) -> int:
	for y in range(DECK_Y + 70, DECK_Y, -1):
		var id := int(tool_.call("get_voxel", Vector3i(x, y, z)))
		if id != VoxelMaterial.AIR and id != VoxelMaterial.LEAVES and id != VoxelMaterial.BARK:
			return y
	return DECK_Y


## Probe the live volume for air under rock, then step outward until the column opens
## to the sky. Proves the galleries daylight instead of being sealed pockets.
func _find_cave_mouth(city: CityRoot) -> Dictionary:
	var terrain: Node = city.get_node_or_null("VoxelTerrain")
	if terrain == null:
		push_error("FAIL no VoxelTerrain node on CityRoot")
		return {}
	var tool_: Object = terrain.call("get_voxel_tool")
	var center := DistrictCoord.center_world(city.spawn_district_coord, CityRoot.VOXEL_SIZE)
	var cx := int(center.x / CityRoot.VOXEL_SIZE)
	var cz := int(center.z / CityRoot.VOXEL_SIZE)
	var hx := DistrictCoord.SIZE_X_VOX / 2 - 8
	var hz := DistrictCoord.SIZE_Z_VOX / 2 - 8
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	var z := cz - hz
	while z < cz + hz:
		var x := cx - hx
		while x < cx + hx:
			if _is_cave(tool_, x, z):
				for dir: Vector2i in dirs:
					var open := _walk_to_daylight(tool_, x, z, dir)
					if open == Vector2i.MAX:
						continue
					var ox := open.x + dir.x * 16
					var oz := open.y + dir.y * 16
					return {
						"inside": Vector3(float(x), float(DECK_Y + 4), float(z))
							* CityRoot.VOXEL_SIZE,
						"outside": Vector3(float(ox), float(DECK_Y + 7), float(oz))
							* CityRoot.VOXEL_SIZE,
					}
			x += 4
		z += 4
	return {}


func _is_cave(tool_: Object, x: int, z: int) -> bool:
	if int(tool_.call("get_voxel", Vector3i(x, DECK_Y + 4, z))) != VoxelMaterial.AIR:
		return false
	return int(tool_.call("get_voxel", Vector3i(x, DECK_Y + 14, z))) in ROCK_IDS


func _walk_to_daylight(tool_: Object, x: int, z: int, dir: Vector2i) -> Vector2i:
	var px := x
	var pz := z
	for _i in range(70):
		px += dir.x
		pz += dir.y
		if int(tool_.call("get_voxel", Vector3i(px, DECK_Y + 4, pz))) != VoxelMaterial.AIR:
			return Vector2i.MAX
		if int(tool_.call("get_voxel", Vector3i(px, DECK_Y + 10, pz))) == VoxelMaterial.AIR:
			return Vector2i(px, pz)
	return Vector2i.MAX


func _road_cells(planner: DistrictPlanner) -> int:
	var n := 0
	for z in range(planner.cells_z):
		for x in range(planner.cells_x):
			if LandUse.is_road(planner.tag_at(x, z)):
				n += 1
	return n


func _district_center(coord: Vector2i) -> Vector3:
	var c := DistrictCoord.center_world(coord, CityRoot.VOXEL_SIZE)
	return Vector3(c.x, 0.0, c.z)


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
	await _settle(8.0)
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

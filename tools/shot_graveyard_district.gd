## Graveyard district look inspection: aerial, path/gate, chapel, and crypt shots.
##
## Run: Godot --path . res://tools/shot_graveyard_district.tscn -- --spawn-theme=graveyard --city-seed=42
extends Node

const AERIAL_PNG := "res://tools/graveyard_aerial.png"
const GATE_PNG := "res://tools/graveyard_gate.png"
const CHAPEL_PNG := "res://tools/graveyard_chapel.png"
const CRYPT_PNG := "res://tools/graveyard_crypt.png"
const ROWS_PNG := "res://tools/graveyard_rows.png"
const DECK_Y := 6
const ROCK_IDS: Array[int] = [
	VoxelMaterial.BEDROCK,
	VoxelMaterial.STONE,
	VoxelMaterial.BRICK,
	VoxelMaterial.BRICK_DARK,
	VoxelMaterial.DIRT,
	VoxelMaterial.GRAVEL,
	VoxelMaterial.CAVE_WALL,
	VoxelMaterial.CAVE_FLOOR,
	VoxelMaterial.GRAVE_STONE,
	VoxelMaterial.GRAVE_MARBLE,
	VoxelMaterial.GRAVE_SOIL,
	VoxelMaterial.GRAVE_PATH,
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
	if theme.id != DistrictTheme.GRAVEYARD:
		push_error("FAIL spawn district is %s, expected Graveyard" % theme.display_name)
		get_tree().quit(1)
		return

	await _settle(10.0)
	var inst := _spawn_district(city)
	if inst == null:
		push_error("FAIL spawn district instance not loaded")
		get_tree().quit(1)
		return
	var planner := inst.generator.get_planner()
	print("graveyard rect %s, road cells %d" % [planner.large_graveyard, _road_cells(planner)])

	var center := _district_center(city.spawn_district_coord)
	walker.global_position = Vector3(center.x, 18.0, center.z)
	await _settle(16.0)

	## Closer oblique so the elevated yard, hedge and chapel read through the fog.
	await _shoot_near(
		walker,
		center + Vector3(-70.0, 45.0, 90.0),
		center + Vector3(0.0, 8.0, 0.0),
		AERIAL_PNG
	)

	var gate := _find_gate(city)
	if gate.is_empty():
		push_error("FAIL no hedge gate / path climb found")
		get_tree().quit(1)
		return
	var gate_out: Vector3 = gate["outside"]
	var gate_in: Vector3 = gate["inside"]
	print("gate approach %s → %s" % [gate_out, gate_in])
	var gate_dir := (gate_in - gate_out).normalized()
	## Walker stands behind the camera so its mesh never fills the frame.
	walker.global_position = gate_out - gate_dir * 3.0 + Vector3(0.0, 3.0, 0.0)
	await _settle(10.0)
	await _shoot(gate_out + Vector3(0.0, 2.4, 0.0), gate_in + Vector3(0.0, 2.5, 0.0), GATE_PNG)

	var aisle := _find_aisle_run(city)
	if aisle.is_empty():
		push_error("FAIL no long plot aisle found")
		get_tree().quit(1)
		return
	var aisle_eye: Vector3 = aisle["eye"]
	var aisle_look: Vector3 = aisle["look"]
	print("aisle run %s → %s" % [aisle_eye, aisle_look])
	walker.global_position = aisle_eye + Vector3(0.0, 2.0, 0.0)
	await _settle(10.0)
	## Stand the camera a few metres down the walk so the walker's own body is behind it.
	var aisle_dir := (aisle_look - aisle_eye).normalized()
	await _shoot(
		aisle_eye + aisle_dir * 4.0 + Vector3(0.0, 1.7, 0.0),
		aisle_look + Vector3(0.0, 1.2, 0.0),
		ROWS_PNG
	)

	var chapel := _find_chapel(city)
	if chapel == Vector3.ZERO:
		push_error("FAIL no chapel roof found")
		get_tree().quit(1)
		return
	print("chapel at %s" % chapel)
	walker.global_position = chapel + Vector3(20.0, 6.0, 26.0)
	await _settle(10.0)
	## Above the yew crowns, or the nave is just a green wall.
	await _shoot(chapel + Vector3(18.0, 11.0, 24.0), chapel + Vector3(0.0, 7.0, 0.0), CHAPEL_PNG)

	walker.global_position = center + Vector3(0.0, 8.0, 0.0)
	await _settle(10.0)
	var crypt := _find_crypt(city)
	if crypt == Vector3.ZERO:
		push_error("FAIL no catacomb air under the yard")
		get_tree().quit(1)
		return
	print("crypt at %s" % crypt)
	walker.global_position = crypt
	await _settle(12.0)
	## Camera pushed off the walker so its mesh does not fill the frame.
	await _shoot(
		crypt + Vector3(1.2, 0.9, 0.6), crypt + Vector3(9.0, 0.6, 4.5), CRYPT_PNG
	)

	print("RESULT: OK")
	get_tree().quit(0)


func _find_gate(city: CityRoot) -> Dictionary:
	var terrain: Node = city.get_node_or_null("VoxelTerrain")
	var tool_: Object = terrain.call("get_voxel_tool")
	var center := DistrictCoord.center_world(city.spawn_district_coord, CityRoot.VOXEL_SIZE)
	var cx := int(center.x / CityRoot.VOXEL_SIZE)
	var cz := int(center.z / CityRoot.VOXEL_SIZE)
	## Find a cinder walk on the elevated yard near a hedge gap (yew nearby, path open).
	for radius: int in [40, 80, 120, 160]:
		var z := cz - radius
		while z < cz + radius:
			var x := cx - radius
			while x < cx + radius:
				var surface := _surface_y(tool_, x, z)
				if surface < DECK_Y + 5:
					x += 3
					continue
				if (
					int(tool_.call("get_voxel", Vector3i(x, surface, z)))
					!= VoxelMaterial.GRAVE_PATH
				):
					x += 3
					continue
				## Prefer columns with hedge yew a few metres sideways (a gate mouth).
				var hedge_near := false
				for step: Vector2i in [
					Vector2i(4, 0), Vector2i(-4, 0), Vector2i(0, 4), Vector2i(0, -4)
				]:
					if (
						int(tool_.call("get_voxel", Vector3i(x + step.x, surface + 2, z + step.y)))
						== VoxelMaterial.YEW
					):
						hedge_near = true
						break
				if not hedge_near and radius < 120:
					x += 3
					continue
				## Approach from whichever side actually drops away down the terraces.
				var out_dir := Vector2i.ZERO
				var out_surface := surface
				for step2: Vector2i in [
					Vector2i(14, 0), Vector2i(-14, 0), Vector2i(0, 14), Vector2i(0, -14)
				]:
					var s2 := _surface_y(tool_, x + step2.x, z + step2.y)
					if s2 < out_surface:
						out_surface = s2
						out_dir = step2
				## Only accept a real rim: the ground has to fall away by a few voxels,
				## otherwise this is just a walk in the middle of the plots.
				if out_dir == Vector2i.ZERO or surface - out_surface < 4:
					x += 3
					continue
				var inside := Vector3(float(x), float(surface), float(z)) * CityRoot.VOXEL_SIZE
				var outside := (
					Vector3(
						float(x + out_dir.x), float(out_surface + 4), float(z + out_dir.y)
					)
					* CityRoot.VOXEL_SIZE
				)
				return {"outside": outside, "inside": inside}
			z += 3
	return {}


## Eye-level view straight down a plot aisle — the shot that shows whether the
## rows and the walks read from the ground.
func _find_aisle_run(city: CityRoot) -> Dictionary:
	var terrain: Node = city.get_node_or_null("VoxelTerrain")
	var tool_: Object = terrain.call("get_voxel_tool")
	var center := DistrictCoord.center_world(city.spawn_district_coord, CityRoot.VOXEL_SIZE)
	var cx := int(center.x / CityRoot.VOXEL_SIZE)
	var cz := int(center.z / CityRoot.VOXEL_SIZE)
	var best_run := 0
	var best: Dictionary = {}
	var z := cz - 90
	while z < cz + 90:
		var x := cx - 90
		while x < cx + 90:
			var surface := _surface_y(tool_, x, z)
			if (
				surface < DECK_Y + 6
				or int(tool_.call("get_voxel", Vector3i(x, surface, z))) != VoxelMaterial.GRAVE_PATH
			):
				x += 2
				continue
			## Skip walks under a canopy — the camera would end up inside a yew.
			var clear := true
			for dy in range(1, 9):
				if int(tool_.call("get_voxel", Vector3i(x, surface + dy, z))) != VoxelMaterial.AIR:
					clear = false
					break
			if not clear:
				x += 2
				continue
			for dir: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var run := 0
				while run < 60:
					var px := x + dir.x * (run + 1)
					var pz := z + dir.y * (run + 1)
					if (
						int(tool_.call("get_voxel", Vector3i(px, surface, pz)))
						!= VoxelMaterial.GRAVE_PATH
					):
						break
					run += 1
				if run > best_run:
					best_run = run
					var eye := Vector3(float(x), float(surface), float(z)) * CityRoot.VOXEL_SIZE
					var look := (
						Vector3(float(x + dir.x * run), float(surface), float(z + dir.y * run))
						* CityRoot.VOXEL_SIZE
					)
					best = {"eye": eye, "look": look}
			x += 2
		z += 2
	if best_run < 12:
		return {}
	return best


func _surface_y(tool_: Object, x: int, z: int) -> int:
	for y in range(DECK_Y + 20, DECK_Y - 1, -1):
		var id := int(tool_.call("get_voxel", Vector3i(x, y, z)))
		if (
			id != VoxelMaterial.AIR
			and id != VoxelMaterial.LEAVES
			and id != VoxelMaterial.YEW
			and id != VoxelMaterial.BARK
		):
			return y
	return DECK_Y


func _find_chapel(city: CityRoot) -> Vector3:
	var terrain: Node = city.get_node_or_null("VoxelTerrain")
	var tool_: Object = terrain.call("get_voxel_tool")
	var center := DistrictCoord.center_world(city.spawn_district_coord, CityRoot.VOXEL_SIZE)
	var cx := int(center.x / CityRoot.VOXEL_SIZE)
	var cz := int(center.z / CityRoot.VOXEL_SIZE)
	## Chapel roof sits well above the elevated yard (deck ≈ 14, ridge ≈ 23–27).
	var z := cz - 120
	while z < cz + 120:
		var x := cx - 120
		while x < cx + 120:
			for y in [24, 26, 22, 28, 20]:
				if int(tool_.call("get_voxel", Vector3i(x, y, z))) == VoxelMaterial.ROOF:
					return Vector3(float(x), float(y - 4), float(z)) * CityRoot.VOXEL_SIZE
			x += 3
		z += 3
	return Vector3.ZERO


func _find_crypt(city: CityRoot) -> Vector3:
	var terrain: Node = city.get_node_or_null("VoxelTerrain")
	var tool_: Object = terrain.call("get_voxel_tool")
	var center := DistrictCoord.center_world(city.spawn_district_coord, CityRoot.VOXEL_SIZE)
	var cx := int(center.x / CityRoot.VOXEL_SIZE)
	var cz := int(center.z / CityRoot.VOXEL_SIZE)
	## Air under the elevated fill with a few metres of headroom and a forward bore.
	var z := cz - 100
	while z < cz + 100:
		var x := cx - 100
		while x < cx + 100:
			var stand_y := -1
			for y in range(DECK_Y + 1, DECK_Y + 8):
				if int(tool_.call("get_voxel", Vector3i(x, y, z))) != VoxelMaterial.AIR:
					continue
				var head := 0
				for dy in range(1, 7):
					if int(tool_.call("get_voxel", Vector3i(x, y + dy, z))) != VoxelMaterial.AIR:
						break
					head += 1
				if head < 4:
					continue
				if int(tool_.call("get_voxel", Vector3i(x, y + head + 1, z))) not in ROCK_IDS:
					continue
				if int(tool_.call("get_voxel", Vector3i(x + 3, y + 2, z))) != VoxelMaterial.AIR:
					continue
				stand_y = y
				break
			if stand_y >= 0:
				return Vector3(float(x), float(stand_y), float(z)) * CityRoot.VOXEL_SIZE
			x += 2
		z += 2
	return Vector3.ZERO


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

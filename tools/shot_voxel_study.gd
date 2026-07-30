## Voxel material study — close wall + floor + scale cube so texel density,
## tiling pitch, and mesh seams can be judged from pixels.
##
##   powershell -File tools\run_test.ps1 shot_voxel_study -Rendered
##   powershell -File tools\run_test.ps1 shot_voxel_study -Rendered -GodotArgs "--material=castle_block"
##   powershell -File tools\run_test.ps1 shot_voxel_study -Rendered -GodotArgs "--material=glass"
##
## Default studies the castle rock family (CASTLE_BLOCK / mossy / STONE / BEDROCK).
extends Node

const OUT_DIR := "res://tools/"
const VOX := 0.5


func _ready() -> void:
	var ids := _resolve_materials()
	var label := _study_label(ids)
	print("VOXEL_STUDY materials: %s" % label)
	for id in ids:
		_report_material(id)

	var root := Node3D.new()
	add_child(root)
	_build_environment(root)

	var terrain := VoxelTerrain.new()
	terrain.scale = Vector3(VOX, VOX, VOX)
	var mesher := VoxelMesherBlocky.new()
	mesher.library = VoxelBlockLibrary.build()
	terrain.mesher = mesher
	const AirGeneratorScript := preload("res://scripts/city/air_generator.gd")
	terrain.generator = AirGeneratorScript.new()
	terrain.bounds = AABB(Vector3(-8, 0, -8), Vector3(48, 24, 48))
	terrain.max_view_distance = 128
	terrain.generate_collisions = false
	root.add_child(terrain)
	var viewer := VoxelViewer.new()
	viewer.view_distance = 128
	viewer.requires_visuals = true
	root.add_child(viewer)

	var tool := terrain.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	var guard := 0
	while not tool.is_area_editable(AABB(Vector3(0, 0, 0), Vector3(36, 14, 36))) and guard < 300:
		guard += 1
		await get_tree().process_frame

	if ids.size() == 1:
		_place_single(tool, ids[0])
	else:
		_place_lineup(tool, ids)

	await get_tree().create_timer(1.5).timeout
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	if ids.size() == 1 and VoxelMaterial.is_room_prop(ids[0]):
		## Room-corner props sit around voxel (4..6, 1, 4..6) → world ~2–3 m.
		cam.global_position = Vector3(3.6, 2.2, 1.4)
		cam.look_at(Vector3(2.5, 0.9, 2.5))
	elif ids.size() == 1:
		## Close enough that fine grain / texel density is readable in the PNG.
		cam.global_position = Vector3(2.0, 2.8, 3.2)
		cam.look_at(Vector3(3.6, 1.8, 5.2))
	elif ids.size() > 0 and VoxelMaterial.is_room_prop(ids[0]):
		cam.global_position = Vector3(14.0, 12.0, -2.0)
		cam.look_at(Vector3(12.0, 0.5, 8.0))
	else:
		cam.global_position = Vector3(1.2, 4.8, -1.2)
		cam.look_at(Vector3(6.5, 1.8, 4.0))
	viewer.global_position = cam.global_position
	await get_tree().create_timer(1.0).timeout

	var out_name := _cli_value("--out=")
	if out_name == "":
		out_name = _default_out_name(label)
	elif not out_name.ends_with(".png"):
		out_name += ".png"
	var out_path := OUT_DIR + out_name
	get_viewport().get_texture().get_image().save_png(out_path)
	print("VOXEL_STUDY wrote %s" % out_path)
	print("RESULT: OK")
	get_tree().quit(0)


func _build_environment(root: Node3D) -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.55, 0.68, 0.82)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.72, 0.78)
	environment.ambient_light_energy = 0.85
	env.environment = environment
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 40, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	root.add_child(sun)


## Single-material deep study: floor sheet + wall curtain + 0.5 m scale cube.
## Room props get a room corner with a few instances (not a solid curtain of chairs).
func _place_single(tool: VoxelTool, id: int) -> void:
	if VoxelMaterial.is_room_prop(id):
		for z in range(1, 12):
			for x in range(1, 12):
				tool.set_voxel(Vector3i(x, 0, z), VoxelMaterial.CASTLE_BLOCK)
		for y in range(1, 5):
			for x in range(1, 12):
				tool.set_voxel(Vector3i(x, y, 10), VoxelMaterial.CASTLE_BLOCK)
			for z in range(1, 11):
				tool.set_voxel(Vector3i(1, y, z), VoxelMaterial.CASTLE_BLOCK)
		tool.set_voxel(Vector3i(4, 1, 4), id)
		tool.set_voxel(Vector3i(6, 1, 4), id)
		tool.set_voxel(Vector3i(5, 1, 6), id)
		return

	var contrast := VoxelMaterial.BRICK if id != VoxelMaterial.BRICK else VoxelMaterial.METAL
	for z in range(1, 14):
		for x in range(1, 14):
			tool.set_voxel(Vector3i(x, 0, z), contrast)

	## Checker under the floor sheet (shows see-through for glass; scale for opaque).
	for z in range(3, 7):
		for x in range(3, 10):
			tool.set_voxel(
				Vector3i(x, 1, z),
				VoxelMaterial.ROOF_CLAY if (x + z) % 2 == 0 else VoxelMaterial.METAL_PLATE
			)

	for z in range(3, 7):
		for x in range(3, 10):
			tool.set_voxel(Vector3i(x, 2, z), id)

	for y in range(1, 7):
		for x in range(3, 10):
			tool.set_voxel(Vector3i(x, y, 11), VoxelMaterial.BRICK_DARK if x % 2 == 0 else VoxelMaterial.METAL)

	for y in range(1, 7):
		for x in range(3, 10):
			tool.set_voxel(Vector3i(x, y, 9), id)

	## Lone voxel at known world size for pitch judgement.
	tool.set_voxel(Vector3i(1, 1, 3), id)


## Side-by-side upright panels + short floor pads for a material family.
## Room props get a floor grid + back wall, not upright panels.
func _place_lineup(tool: VoxelTool, ids: Array[int]) -> void:
	var props := ids.size() > 0 and VoxelMaterial.is_room_prop(ids[0])
	if not props:
		var width := 4 + ids.size() * 5
		for z in range(0, 12):
			for x in range(0, width):
				tool.set_voxel(Vector3i(x, 0, z), VoxelMaterial.BRICK)

	if props:
		## Grid on the floor with a back wall — fits the full catalog.
		var cols := 12
		var rows := int(ceili(float(ids.size()) / float(cols)))
		var grid_w := 2 + cols * 2
		var grid_d := 2 + rows * 2
		for z in range(0, grid_d + 2):
			for x in range(0, grid_w + 2):
				tool.set_voxel(Vector3i(x, 0, z), VoxelMaterial.CASTLE_BLOCK)
		for y in range(1, 4):
			for x in range(0, grid_w + 2):
				tool.set_voxel(Vector3i(x, y, grid_d + 1), VoxelMaterial.CASTLE_BLOCK)
		for i in range(ids.size()):
			var col := i % cols
			var row := int(i / cols)
			tool.set_voxel(Vector3i(2 + col * 2, 1, 2 + row * 2), ids[i])
		return

	for i in range(ids.size()):
		var id := ids[i]
		var x0 := 2 + i * 5
		for y in range(1, 7):
			for x in range(x0, x0 + 3):
				tool.set_voxel(Vector3i(x, y, 8), id)
		for z in range(3, 6):
			for x in range(x0, x0 + 3):
				tool.set_voxel(Vector3i(x, 1, z), id)
		## Scale cube beside the panel.
		tool.set_voxel(Vector3i(x0 - 1, 1, 5), id)


func _report_material(id: int) -> void:
	var spec := VoxelSurfaceSpec.for_id(id)
	var albedo_path := VoxelBlockLibrary.TEX_DIR + spec.albedo_file
	var tex := load(albedo_path) as Texture2D
	var w := 0
	var h := 0
	var mips := false
	var fmt := "?"
	if tex != null:
		var img := tex.get_image()
		if img != null:
			w = img.get_width()
			h = img.get_height()
			mips = img.has_mipmaps()
			fmt = str(img.get_format())
	var texels_per_m := 0.0
	if spec.tile_meters.x > 0.001 and w > 0:
		texels_per_m = float(w) / spec.tile_meters.x
	print(
		(
			"STUDY id=%d name=%s albedo=%s %dx%d mips=%s fmt=%s tile_m=%s texels/m=%.0f roughness=%.2f"
			% [
				id,
				_material_name(id),
				spec.albedo_file,
				w,
				h,
				mips,
				fmt,
				spec.tile_meters,
				texels_per_m,
				spec.roughness,
			]
		)
	)


func _resolve_materials() -> Array[int]:
	var flag := _cli_value("--material=")
	if flag == "":
		## Castle rock family — what the user called out.
		return [
			VoxelMaterial.CASTLE_BLOCK,
			VoxelMaterial.CASTLE_BLOCK_MOSSY,
			VoxelMaterial.STONE,
			VoxelMaterial.BEDROCK,
		] as Array[int]
	if flag == "props" or flag == "room_props" or flag == "furniture":
		var all_props: Array[int] = []
		for i in range(RoomPropCatalog.PROP_COUNT):
			all_props.append(RoomPropCatalog.PROP_FIRST + i)
		return all_props
	var id := _parse_material(flag)
	if id < 0:
		push_error("Unknown --material=%s" % flag)
		get_tree().quit(1)
		return [] as Array[int]
	return [id] as Array[int]


func _study_label(ids: Array[int]) -> String:
	if ids.size() == 1:
		return _material_name(ids[0]).to_lower()
	if ids.size() > 1 and VoxelMaterial.is_room_prop(ids[0]):
		return "props"
	return "rock"


func _default_out_name(label: String) -> String:
	return "voxel_study_%s.png" % label


func _cli_value(prefix: String) -> String:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with(prefix):
			return s.substr(prefix.length()).strip_edges().to_lower()
	return ""


func _parse_material(raw: String) -> int:
	match raw:
		"glass":
			return VoxelMaterial.GLASS
		"glass_lit":
			return VoxelMaterial.GLASS_LIT
		"castle", "castle_block", "ashlar":
			return VoxelMaterial.CASTLE_BLOCK
		"castle_mossy", "castle_block_mossy", "mossy":
			return VoxelMaterial.CASTLE_BLOCK_MOSSY
		"stone":
			return VoxelMaterial.STONE
		"bedrock", "rock":
			return VoxelMaterial.BEDROCK
		"cave", "cave_wall":
			return VoxelMaterial.CAVE_WALL
		"brick":
			return VoxelMaterial.BRICK
		"rock_family", "rocks":
			return -2
	if raw.is_valid_int():
		var n := raw.to_int()
		if n > 0 and n < VoxelMaterial.COUNT:
			return n
	## Catalog stem (chair, bedDouble, lampRoundTable, …).
	var prop_id := RoomPropCatalog.find_stem(raw)
	if prop_id >= RoomPropCatalog.PROP_FIRST:
		return prop_id
	var camel := raw.replace("-", "").replace("_", "")
	prop_id = RoomPropCatalog.find_stem(camel)
	if prop_id >= RoomPropCatalog.PROP_FIRST:
		return prop_id
	return -1


func _material_name(id: int) -> String:
	if VoxelMaterial.is_room_prop(id):
		return RoomPropCatalog.stem_of(id)
	match id:
		VoxelMaterial.GLASS:
			return "GLASS"
		VoxelMaterial.GLASS_LIT:
			return "GLASS_LIT"
		VoxelMaterial.CASTLE_BLOCK:
			return "CASTLE_BLOCK"
		VoxelMaterial.CASTLE_BLOCK_MOSSY:
			return "CASTLE_BLOCK_MOSSY"
		VoxelMaterial.STONE:
			return "STONE"
		VoxelMaterial.BEDROCK:
			return "BEDROCK"
		VoxelMaterial.CAVE_WALL:
			return "CAVE_WALL"
		VoxelMaterial.BRICK:
			return "BRICK"
		_:
			return "ID_%d" % id
